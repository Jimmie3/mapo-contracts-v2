// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Utils} from "./libs/Utils.sol";
import {IReceiver} from "./interfaces/IReceiver.sol";
import {IRelay} from "./interfaces/IRelay.sol";
import {ITSSManager} from "./interfaces/ITSSManager.sol";
import {IVaultToken} from "./interfaces/IVaultToken.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IMintableToken} from "./interfaces/IMintableToken.sol";
import {IGasService} from "./interfaces/IGasService.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";
import {IVaultManager} from "./interfaces/IVaultManager.sol";
import {ISwap} from "./interfaces/ISwap.sol";
import {IAffiliateFeeManager} from "./interfaces/IAffiliateFeeManager.sol";

import {TxType, TxInItem, TxOutItem, ChainType, TxItem, GasInfo, BridgeItem} from "./libs/Types.sol";

import {Errs} from "./libs/Errors.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BaseGateway} from "./base/BaseGateway.sol";

contract Relay is BaseGateway, IRelay {
    uint256 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps

    mapping(uint256 => uint256) private chainSequence;
    mapping(uint256 => uint256) private chainLastScanBlock;

    mapping(bytes32 => bool) private outOrderExecuted;

    IPeriphery public periphery;
    IVaultManager public vaultManager;

    struct OrderInfo {
        bool signed;
        uint64 height;
        address gasToken;
        uint128 estimateGas;
        bytes32 hash;
    }

    mapping(bytes32 => OrderInfo) public orderInfos;

    event SetSwap(address _swap);
    event SetPeriphery(address _periphery);
    event SetVaultManager(address _vaultManager);
    event SetAffiliateFeeManager(address _affiliateFeeManager);

    event Withdraw(address token, address reicerver, uint256 vaultAmount, uint256 tokenAmount);

    event Deposit(bytes32 orderId, uint256 fromChain, address token, uint256 amount, address to, bytes from);

    event TransferIn(bytes32 orderId, address token, uint256 amount, address to, bool result);

    event BridgeRelay(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txType,
        bytes vault,
        bytes to,
        bytes token,
        uint256 amount,
        uint256 sequence,
        // tss sign base on this hash
        // abi.encodePacked(orderId | chainAndGasLimit | txOutType | vault | sequence | token | amount| from | to | keccak256(data)
        bytes32 hash,
        bytes from,
        // tokenOut: bytes(payload)
        // migrate: bytes("vault")
        bytes data
    );


    event BridgeRelaySigned(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,
        bytes vault,
        bytes relayData,
        bytes signature
    );

    event BridgeCompleted(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | reserved (16 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txOutType,
        bytes vault,
        uint256 sequence,
        address sender,
        bytes data
    );

    event BridgeError(bytes32 indexed orderId, string reason);
    event BridgeFeeCollected(bytes32 indexed orderId, address token, uint256 protocolFee);

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setVaultManager(address _vaultManager) external restricted {
        require(_vaultManager != address(0));
        vaultManager = IVaultManager(_vaultManager);
        emit SetVaultManager(_vaultManager);
    }

    function setPeriphery(address _periphery) external restricted {
        require(_periphery != address(0));
        periphery = IPeriphery(_periphery);
        emit SetPeriphery(_periphery);
    }

    function addChain(uint256 chain, uint256 startBlock) external override {
        _checkAccess(3);
        _updateLastScanBlock(chain, uint64(startBlock));
        vaultManager.addChain(chain);
        // todo: emit event
    }


    function removeChain(uint256 chain) external override {
        _checkAccess(3);
        // todo: check vault migration
        (bool completed,) = vaultManager.checkMigration();
        if (!completed) revert Errs.migration_not_completed();
        vaultManager.removeChain(chain);
        // todo: emit event
    }

    function isOrderExecuted(bytes32 orderId, bool isTxIn) external view override returns (bool executed) {
        executed = isTxIn ? orderExecuted[orderId] : outOrderExecuted[orderId];
    }


    function getChainLastScanBlock(uint256 chain) external view override returns(uint256) {
        return chainLastScanBlock[chain];
    }

    function redeem(address _vaultToken, uint256 _vaultShare, address receiver) external whenNotPaused {
        address user = msg.sender;

        uint256 amount = vaultManager.redeem(_vaultToken, _vaultShare, user, receiver);

        emit Withdraw(_vaultToken, user, _vaultShare, amount);
    }


    function rotate(bytes memory retiringVault, bytes memory activeVault) external override {
        _checkAccess(4);

        vaultManager.rotate(retiringVault, activeVault);
    }

    function migrate() external override returns (bool) {
        _checkAccess(4);

        (bool completed, TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault) = vaultManager.migrate();
        if (completed) {
            return true;
        }
        if (txItem.chain == 0) {
            // no need do more migration, waiting for all migration completed
            return false;
        }

        txItem.orderId = _getOrderId();

        BridgeItem memory bridgeItem;
        bridgeItem.vault = fromVault;
        bridgeItem.payload = toVault;
        bridgeItem.txType = TxType.MIGRATE;

        _emitRelay(selfChainId, bridgeItem, txItem, gasInfo);

        return false;
    }

    function relaySigned(bytes32 orderId, bytes calldata relayData, bytes calldata signature)
        external
    {
        OrderInfo storage order = orderInfos[orderId];
        if (order.signed) return;

        BridgeItem memory outItem = abi.decode(relayData, (BridgeItem));

        bytes32 hash = _getSignHash(orderId, outItem);
        if (hash != order.hash) revert Errs.invalid_signature();

        address signer = ECDSA.recover(hash, signature);
        if (signer != Utils.getAddressFromPublicKey(outItem.vault)) revert Errs.invalid_signature();

        order.signed = true;
        _updateLastScanBlock(selfChainId, order.height);

        emit BridgeRelaySigned(orderId, outItem.chainAndGasLimit, outItem.vault, relayData, signature);
    }

    // todo: add block hash
    function postNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionSize,
        uint256 transactionSizeWithCall,
        uint256 transactionRate
    ) external override {
        _checkAccess(4);

        IGasService gasService = IGasService(periphery.getAddress(1));
        gasService.postNetworkFee(chain, height, transactionSize, transactionSizeWithCall, transactionRate);
    }

    function executeTxOut(TxOutItem calldata txOutItem) external override {
        _checkAccess(4);

        if (outOrderExecuted[txOutItem.orderId]) revert Errs.order_executed();

        BridgeItem memory bridgeItem = txOutItem.bridgeItem;

        uint256 chain = (bridgeItem.chainAndGasLimit >> 128) & 0xFFFFFFFFFFFFFFFF;
        _updateLastScanBlock(chain, txOutItem.height);

        TxItem memory txItem;
        txItem.orderId = txOutItem.orderId;
        txItem.chain = chain;
        txItem.chainType = _getRegistry().getChainType(chain);

        OrderInfo memory order = orderInfos[txOutItem.orderId];

        uint256 usedGas = order.estimateGas;
        if (txItem.chainType != ChainType.CONTRACT) {
            usedGas = _getRelayChainGasAmount(chain, txOutItem.gasUsed);
        }

        if (vaultManager.checkVault(txItem.chainType, txItem.chain, bridgeItem.vault)) {
            uint256 gasAmount = 0;
            uint256 transferAmount = 0;

            (txItem.token, txItem.amount) = _getRelayTokenAndAmount(chain, bridgeItem.token, bridgeItem.amount);

            if (bridgeItem.txType == TxType.MIGRATE) {
                (gasAmount, transferAmount) = vaultManager.migrationComplete(txItem, bridgeItem.vault, bridgeItem.payload, order.estimateGas, usedGas);
            } else {
                (gasAmount, transferAmount) = vaultManager.transferComplete(txItem, bridgeItem.vault, usedGas, order.estimateGas);
            }
            if (gasAmount > 0) {
                _sendToken(txItem.token, gasAmount, txOutItem.sender, true);
            }
            if (transferAmount > 0) {
                _checkAndBurn(txItem.token, transferAmount);
            }

        } else {
            // refund from retired vault on non-contract vault
        }

        delete orderInfos[txItem.orderId];

        emit BridgeCompleted(
            txOutItem.orderId,
            bridgeItem.chainAndGasLimit,
            bridgeItem.txType,
            bridgeItem.vault,
            bridgeItem.sequence,
            txOutItem.sender,
            bridgeItem.payload
        );
    }

    // payload |1byte affiliate count| n * 2 byte affiliateId + 2 byte fee rate| 2 byte relayOutToken|
    // 30 byte relayMinAmountOut| target call data|

    // swap: affiliate data | relay data | target data
    function executeTxIn(TxInItem memory txInItem) external override {
        if (orderExecuted[txInItem.orderId]) revert Errs.order_executed();

        _checkAccess(4);

        BridgeItem memory bridgeItem = txInItem.bridgeItem;

        uint256 fromChain = bridgeItem.chainAndGasLimit >> 192;
        uint256 toChain = bridgeItem.chainAndGasLimit >> 128 & 0xFFFFFFFFFFFFFFFF;

        _updateLastScanBlock(fromChain, txInItem.height);

        TxItem memory txItem;
        txItem.orderId = txInItem.orderId;
        (txItem.token, txItem.amount) = _getRelayTokenAndAmount(fromChain, bridgeItem.token, bridgeItem.amount);
        _checkAndMint(txItem.token, txItem.amount);

        txItem.chain = fromChain;
        txItem.chainType = periphery.getChainType(fromChain);
        if (!vaultManager.checkVault(txItem.chainType, txItem.chain, bridgeItem.vault)) {
            // refund if vault is retired
            bridgeItem.to = txInItem.refundAddr;
            bridgeItem.payload = bytes("");

            return _refund(bridgeItem, txItem, true);
        }

        if (bridgeItem.txType == TxType.DEPOSIT) {
            txItem.to = Utils.fromBytes(bridgeItem.to);
            _depositIn(txItem, bridgeItem.from, bridgeItem.vault);
        } else {
            (bytes memory affiliateData, bytes memory relayData, bytes memory targetData) =
                abi.decode(bridgeItem.payload, (bytes, bytes, bytes));

            // collect affiliate and protocol fee first
            txItem.amount = _collectAffiliateAndProtocolFee(txItem, affiliateData);
            if (txItem.amount == 0) {
                // emit complete event
                emit BridgeError(txItem.orderId, "zero out amount");
                return;
            }

            try this.execute(bridgeItem, txItem, toChain, relayData, targetData) returns (uint256 amount) {
                txItem.amount = amount;

                txItem.chain = toChain;
                txItem.chainType = periphery.getChainType(txItem.chain);
            } catch (bytes memory) {
                // txItem.chain = fromChain;
                // txItem.chainType = periphery.getChainType(fromChain);

                bridgeItem.to = txInItem.refundAddr;
                bridgeItem.payload = bytes("");

                _refund(bridgeItem, txItem, false);

                return;
            }

            if (txItem.chain == selfChainId) {
                return _bridgeIn(txItem, bridgeItem);
            }
        }
    }

    function _swap(address tokenIn, uint256 amountInt, bytes memory payload) internal returns (address , uint256) {
        (address tokenOut, uint256 amountOutMin) = abi.decode(payload, (address, uint256));
        ISwap swap = ISwap(periphery.getSwap());
        // todo: approve or send token to swap
        uint amountOut = swap.swap(tokenIn, amountInt, tokenOut, amountOutMin);
        return (tokenOut, amountOut);
    }

    function execute(BridgeItem memory bridgeItem, TxItem memory txItem, uint256 toChain, bytes memory relayPayload, bytes memory targetPayload) public returns (uint256) {
        require(msg.sender == address(this));

        bool choose;
        GasInfo memory gasInfo;
        uint256 fromChain = txItem.chain;

        if (relayPayload.length > 0) {
            // 1.1 collect from chain vault fee and balance fee
            // 1.2 update from chain vault
            txItem.amount = vaultManager.transferIn(txItem, bridgeItem.vault, toChain);

            // 2 swap
            (txItem.token, txItem.amount) = _swap(txItem.token, txItem.amount, relayPayload);

            // todo: update target payload
            txItem.chain = toChain;
            txItem.chainType = periphery.getChainType(toChain);

            // 3.1 collect to chain vault fee and balance fee
            // 3.2 calculate to chain gas fee
            // 3.3 choose to chain vault
            // 3.4 update to chain vault
            (choose, txItem.amount, bridgeItem.vault, gasInfo) = vaultManager.transferOut(txItem, fromChain, targetPayload.length > 0);
            if (!choose) {
                // no vault
                revert Errs.invalid_vault();
            }
        } else {
            // 1 collect vault fee and balance fee

            // 2.1 calculate to chain gas fee
            // 2.2 choose to chain vault

            // 3 update from chain and to chain vault
            (choose, txItem.amount, bridgeItem.vault, gasInfo) = vaultManager.bridge(txItem,bridgeItem.vault,  toChain,targetPayload.length > 0);
            if (!choose) {
                // no vault
                revert Errs.invalid_vault();
            }
        }

        // todo: check relay min amount

        bridgeItem.payload = targetPayload;
        bridgeItem.txType = TxType.TRANSFER;

        // 4 emit BridgeRelay event
        if (txItem.chain != selfChainId) {
            _emitRelay(fromChain, bridgeItem, txItem, gasInfo);
        }

        return txItem.amount;
    }

    function _bridgeIn(TxItem memory txItem, BridgeItem memory bridgeItem) internal {
        txItem.to = Utils.fromBytes(bridgeItem.to);
        emit BridgeIn(
            txItem.orderId,
            bridgeItem.chainAndGasLimit,
            bridgeItem.txType,
            bridgeItem.vault,
            bridgeItem.sequence,
            msg.sender,
            txItem.token,
            txItem.amount,
            txItem.to,
            bridgeItem.payload
        );
        _bridgeTokenIn(txItem.orderId, bridgeItem, txItem);
    }

    function _getActiveVault() internal view override returns (bytes memory vault) {
        return vaultManager.getActiveVault();
    }

    function _deposit(bytes32 orderId, address outToken, uint256 amount, address from, address to, address)
        internal
        override
    {
        TxItem memory txItem = TxItem(orderId, selfChainId, ChainType.CONTRACT, outToken, amount, to);
        bytes memory vault = vaultManager.getActiveVault();

        _depositIn(txItem,  Utils.toBytes(from), vault);
    }

    function _bridgeOut(
        bytes32 orderId,
        address token,
        uint256 amount,
        uint256 toChain,
        bytes memory to,
        bytes memory payload
    ) internal override {
        TxItem memory txItem;
        txItem.orderId = orderId;
        txItem.token = token;
        txItem.amount = amount;
        txItem.chain = toChain;

        BridgeItem memory bridgeItem;
        bridgeItem.from = Utils.toBytes(msg.sender);
        bridgeItem.to = to;

        (bytes memory affiliateData, bytes memory relayPayload, bytes memory targetPayload) =
            abi.decode(payload, (bytes, bytes, bytes));

        // collect affiliate and bridge fee first
        txItem.amount = _collectAffiliateAndProtocolFee(txItem, affiliateData);
        if (txItem.amount == 0) revert Errs.zero_amount_out();

        execute(bridgeItem, txItem, selfChainId, relayPayload, targetPayload);
    }


    function _collectAffiliateAndProtocolFee(TxItem memory txItem, bytes memory affiliateData)
    internal
    returns (uint256)
    {
        uint256 affiliateFee;
        if (affiliateData.length > 0) {
            IAffiliateFeeManager affiliateFeeManager = IAffiliateFeeManager(periphery.getAffiliateManager());
            try affiliateFeeManager.collectAffiliatesFee(txItem.orderId, txItem.token, txItem.amount, affiliateData) returns (uint256 totalFee) {
                affiliateFee = totalFee;
                _sendToken(txItem.token, affiliateFee, address(affiliateFeeManager), true);
            } catch (bytes memory) {
                // do nothing
            }
        }

        (address receiver, uint256 protocolFee) = periphery.getProtocolFee(txItem.token, txItem.amount);
        _sendToken(txItem.token, protocolFee, receiver, true);

        uint256 amount = txItem.amount - affiliateFee - protocolFee;

        emit BridgeFeeCollected(txItem.orderId, txItem.token, protocolFee);

        return amount;
    }


    function _updateLastScanBlock(uint256 chain, uint64 height) internal {
        if (height > chainLastScanBlock[chain]) {
            chainLastScanBlock[chain] = height;
        }
    }

    function _refund(BridgeItem memory bridgeItem, TxItem memory txItem, bool fromRetiredVault) internal {
        GasInfo memory gasInfo;

        // refund to the from vault
        (txItem.amount, gasInfo) = vaultManager.refund(txItem, bridgeItem.vault, fromRetiredVault);
        if (txItem.amount == 0) {
            emit BridgeError(txItem.orderId, "zero out amount");
            return;
        }

        bridgeItem.txType = TxType.REFUND;
        _emitRelay(txItem.chain, bridgeItem, txItem, gasInfo);
    }

    function _depositIn(TxItem memory txItem, bytes memory from, bytes memory vault) internal {
        vaultManager.deposit(txItem, vault);

        emit Deposit(txItem.orderId, txItem.chain, txItem.token, txItem.amount, txItem.to, from);
    }

    function _sendToken(address token, uint256 amount, address to, bool handle) internal returns (bool result) {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        result = (success && (data.length == 0 || abi.decode(data, (bool))));
        if (!handle && !result) revert Errs.transfer_token_out_failed();
    }


    /**
     * @dev Emit bridge relay event and prepare cross-chain transaction
     * Main purpose:
     * 1. Burn tokens on relay chain (except for contract chain migrations)
     * 2. Convert token and amount to target chain format
     * 3. Generate sequence number for target chain
     * 4. Store order information including gas estimate and block height
     * 5. Calculate and store signature hash for TSS signing
     * 6. Emit BridgeRelay event for off-chain relayers to process
     *
     * Calling requirements:
     * - Vault must be already selected and updated before calling this function
     * - VaultManager.doTransfer() or similar vault update must be called first
     * - txItem must contain valid orderId, token, amount, and chain information
     * - bridgeItem must contain valid vault, from, to, payload and txType
     *
     * @param fromChain Source chain ID where the transaction originates
     * @param bridgeItem Bridge item containing vault and transaction details
     * @param txItem Transaction item with token and amount information
     * @param gasInfo Estimated gas required for the transaction on target chain
     */
    function _emitRelay(uint256 fromChain, BridgeItem memory bridgeItem, TxItem memory txItem, GasInfo memory gasInfo) internal {

        // non contract migration or token transfer
        if (!(bridgeItem.txType == TxType.MIGRATE && txItem.chainType == ChainType.CONTRACT)) {
            // _checkAndBurn(txItem.token, txItem.amount);
            (bridgeItem.token, bridgeItem.amount) = _getToChainTokenAndAmount(txItem.chain, txItem.token, txItem.amount);
        }

        bridgeItem.chainAndGasLimit =
                        _getChainAndGasLimit(fromChain, txItem.chain, gasInfo.transactionRate, gasInfo.transactionSize);
        bridgeItem.sequence = ++chainSequence[txItem.chain];

        OrderInfo storage order = orderInfos[txItem.orderId];
        order.gasToken = txItem.token;
        order.estimateGas = gasInfo.estimateGas;

        order.hash = _getSignHash(txItem.orderId, bridgeItem);
        order.height = uint64(block.number);

        emit BridgeRelay(
            txItem.orderId,
            bridgeItem.chainAndGasLimit,
            bridgeItem.txType,
            bridgeItem.vault,
            bridgeItem.to,
            bridgeItem.token,
            bridgeItem.amount,
            bridgeItem.sequence,
            order.hash,
            bridgeItem.from,
            bridgeItem.payload
        );
    }


    function _getRelayChainGasAmount(uint256 chain, uint256 gasAmount) internal view returns (uint256 relayGasAmount) {
        address gasToken = _getRegistry().getChainGasToken(chain);
        bytes memory toToken = _getRegistry().getToChainToken(gasToken, chain);

        relayGasAmount = _getRegistry().getRelayChainAmount(toToken, chain, gasAmount);
    }

    function _getRelayTokenAndAmount(uint256 chain, bytes memory fromToken, uint256 fromAmount) internal view returns (address token, uint256 amount){
        IRegistry registry = _getRegistry();

        token = registry.getRelayChainToken(chain, fromToken);
        amount = registry.getRelayChainAmount(fromToken, chain, fromAmount);
    }

    function _getToChainTokenAndAmount(uint256 chain, address relayToken, uint256 relayAmount) internal view returns (bytes memory token, uint256 amount){
        IRegistry registry = _getRegistry();

        token = registry.getToChainToken(relayToken, chain);
        amount = registry.getToChainAmount(relayToken, relayAmount, chain);
    }


    function _getOrderId() internal returns (bytes32 orderId) {
        return keccak256(abi.encodePacked(selfChainId, address(this), ++nonce));
    }

    function _getRegistry() internal view returns (IRegistry registry) {
        registry = IRegistry(periphery.getAddress(3));
    }

    function _getChainAndGasLimit(uint256 _fromChain, uint256 _toChain, uint256 _transactionRate, uint256 _transactionSize)
        internal
        pure
        returns (uint256 chainAndGasLimit)
    {
        chainAndGasLimit = ((_fromChain << 192) | (_toChain << 128) | (_transactionRate << 64) | _transactionSize);
    }

    function _checkAccess(uint256 t) internal view {
        if (msg.sender != periphery.getAddress(t)) revert Errs.no_access();
    }
}
