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
    mapping(uint256 => uint256) private chainSequence;
    mapping(uint256 => uint256) private chainLastScanBlock;

    mapping(bytes32 => bool) private outOrderExecuted;

    IPeriphery public periphery;
    IVaultManager public vaultManager;

    IAffiliateFeeManager public affiliateFeeManager;
    ISwap public swap;

    struct OrderInfo {
        bool signed;
        uint64 height;
        address gasToken;
        uint256 estimateGas;
        bytes32 hash;
    }

    mapping(bytes32 => OrderInfo) public orderInfos;

    // token => amount
    mapping(address => uint256) public balanceFeeInfos;

    mapping(address => uint256) public vaultFeeInfos;

    address public securityFeeReceiver;


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

    event BridgeFeeCollected(bytes32 indexed orderId, address token, uint256 securityFee, uint256 vaultFee);


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

    function setAffiliateFeeManager(address _affiliateFeeManager) external restricted {
        require(_affiliateFeeManager != address(0));
        affiliateFeeManager = IAffiliateFeeManager(_affiliateFeeManager);
        emit SetAffiliateFeeManager(_affiliateFeeManager);
    }

    function setSwap(address _swap) external restricted {
        require(_swap != address(0));
        swap = ISwap(_swap);
        emit SetSwap(_swap);
    }

    function removeChain(uint256 chain) external override {
        _checkAccess(3);
        // todo: check vault migration
        (bool completed,) = vaultManager.checkMigration();
        if (!completed) revert Errs.migration_not_completed();
        vaultManager.removeChain(chain);
        // todo: emit event
    }

    function withdraw(address _vaultToken, uint256 _vaultAmount) external whenNotPaused {
        address user = msg.sender;
        address token = IVaultToken(_vaultToken).getTokenAddress();
        address vaultToken = _getRegistry().getVaultToken(token);
        if (_vaultToken != vaultToken) revert Errs.invalid_vault_token();
        uint256 amount = IVaultToken(vaultToken).getTokenAmount(_vaultAmount);
        IVaultToken(vaultToken).withdraw(selfChainId, _vaultAmount, user);

        _sendToken(token, amount, user, false);
        emit Withdraw(token, user, _vaultAmount, amount);
    }



    function isOrderExecuted(bytes32 orderId, bool isTxIn) external view override returns (bool executed) {
        executed = isTxIn ? orderExecuted[orderId] : outOrderExecuted[orderId];
    }


    function getChainLastScanBlock(uint256 chain) external view override returns(uint256) {
        return chainLastScanBlock[chain];
    }


    function addChain(uint256 chain, uint256 startBlock) external override {
        _checkAccess(3);
        _updateLastScanBlock(chain, uint64(startBlock));
        vaultManager.addChain(chain);
        // todo: emit event
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
        _migrate(txItem, gasInfo, fromVault, toVault);

        return false;
    }

    function relaySigned(bytes32 orderId, bytes calldata vault, bytes calldata relayData, bytes calldata signature)
        external
    {
        OrderInfo storage order = orderInfos[orderId];
        if (order.signed) return;

        BridgeItem memory outItem = abi.decode(relayData, (BridgeItem));

        bytes32 hash = _getSignHash(orderId, vault, outItem);
        if (hash != order.hash) revert Errs.invalid_signature();

        address signer = ECDSA.recover(hash, signature);
        if (signer != Utils.getAddressFromPublicKey(vault)) revert Errs.invalid_signature();

        order.signed = true;
        _updateLastScanBlock(selfChainId, order.height);

        emit BridgeRelaySigned(orderId, outItem.chainAndGasLimit, vault, relayData, signature);
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

        uint256 relayGasUsed = _getRelayChainGasAmount(chain, txOutItem.gasUsed);

        OrderInfo memory order = orderInfos[txOutItem.orderId];
        uint256 relayGasEstimated = order.estimateGas;
        if (txItem.chainType == ChainType.CONTRACT) {
            // send gas fee to sender
            _sendToken(order.gasToken, order.estimateGas, txOutItem.sender, false);
        }
        if (bridgeItem.txType == TxType.MIGRATE) {
            if (txItem.chainType != ChainType.CONTRACT) {
                (txItem.token, txItem.amount) = _getRelayTokenAndAmount(chain, bridgeItem.token, bridgeItem.amount);
                // todo: mint token
                // _checkAndMint(txItem.token, txItem.amount);
                // send gas to vault
            }
            vaultManager.migrationOut(txItem, bridgeItem.vault, bridgeItem.payload, relayGasUsed, relayGasEstimated);
        } else {
            (txItem.token, txItem.amount) = _getRelayTokenAndAmount(chain, bridgeItem.token, bridgeItem.amount);

            vaultManager.transferOut(
                txItem.chain, bridgeItem.vault, txItem.token, txItem.amount, relayGasUsed, relayGasEstimated
            );
        }

        // todo: delete order info
        // delete orderInfos[orderId];

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

    function _getRelayChainGasAmount(uint256 chain, uint256 gasAmount) internal view returns (uint256 relayGasAmount) {
        bytes memory token = _getToChainToken(chain, _getRegistry().getChainGasToken(chain));
        relayGasAmount = _getRelayAmount(chain, token, gasAmount);
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

            return _refund(bridgeItem, txItem);
        }

        if (bridgeItem.txType == TxType.DEPOSIT) {
            // todo: affiliate fee ?
            // todo: mint vault token in vaultManager
            vaultManager.deposit(txItem, bridgeItem.vault);
            _depositIn(
                txItem.orderId, fromChain, txItem.token, txItem.amount, bridgeItem.from, Utils.fromBytes(bridgeItem.to)
            );
        } else {
            (bytes memory affiliateData, bytes memory relayData, bytes memory targetData) =
                abi.decode(bridgeItem.payload, (bytes, bytes, bytes));

            // collect affiliate and bridge fee first
            txItem.amount = _collectAffiliateAndBridgeFee(txItem, bridgeItem.from, toChain, affiliateData, targetData.length > 0);
            if (txItem.amount == 0) {
                // emit complete event
                return;
            }

            txItem.chain = toChain;
            txItem.chainType = periphery.getChainType(txItem.chain);

            try this.execute(bridgeItem, txItem, fromChain, relayData, targetData) returns (uint256 amount) {
                txItem.amount = amount;
            } catch (bytes memory) {
                txItem.chain = fromChain;
                txItem.chainType = periphery.getChainType(fromChain);

                bridgeItem.to = txInItem.refundAddr;
                bridgeItem.payload = bytes("");

                _refund(bridgeItem, txItem);

                return;
            }

            if (txItem.chain == selfChainId) {
                return _bridgeIn(txItem, bridgeItem);
            }
        }
    }


    function execute(BridgeItem memory bridgeItem, TxItem memory txItem, uint256 fromChain, bytes memory relayPayload, bytes memory targetPayload) public returns (uint256) {
        require(msg.sender == address(this));

        if (relayPayload.length > 0) {
            // todo: update transfer in vault

            // collect fee

            (address tokenOut, uint256 amountOutMin) = abi.decode(relayPayload, (address, uint256));
            txItem.amount = swap.swap(txItem.token, txItem.amount, tokenOut, amountOutMin);
            txItem.token = tokenOut;

            // todo: update target payload
        }

        // get balance fee
        (uint256 balanceFee, bool incentive) = vaultManager.getBalanceFee(fromChain, txItem.chain, txItem.token, txItem.amount);
        if (incentive) {
            txItem.amount += balanceFee;
        } else {
            if (txItem.amount < balanceFee) {
                txItem.amount -= balanceFee;
            } else {
                revert Errs.zero_amount_out();
            }
        }

        bridgeItem.payload = targetPayload;
        bridgeItem.txType = TxType.TRANSFER;

        if (txItem.chain != selfChainId) {
            bool choose;
            GasInfo memory gasInfo;
            (choose, txItem.amount, bridgeItem.vault, gasInfo) = vaultManager.chooseAndTransfer(txItem, targetPayload.length > 0);
            if (!choose) {
                // no vault
                revert Errs.invalid_vault();
            }

            _emitRelay(fromChain, bridgeItem, txItem, gasInfo);
        }

        // todo: check relay min amount

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
        _depositIn(orderId, selfChainId, outToken, amount, Utils.toBytes(from), to);
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
        txItem.amount = _collectAffiliateAndBridgeFee(txItem, bridgeItem.from, toChain, affiliateData, targetPayload.length > 0);
        if (txItem.amount == 0) revert Errs.zero_amount_out();

        execute(bridgeItem, txItem, selfChainId, relayPayload, targetPayload);
    }

    function _collectToChainFee(bytes memory from, TxItem memory txItem, uint256 fromChain, bool withCall)
        internal view
        returns (uint256 outAmount)
    {
        (uint256 securityFee, uint256 vaultFee) =
            _getRegistry().getTransferOutFee(from, txItem.token, txItem.amount, fromChain, txItem.chain, withCall);


        if (txItem.amount > securityFee + vaultFee) {
            outAmount = txItem.amount - securityFee - vaultFee;
        } else {
            securityFee = txItem.amount;
            outAmount = 0;
        }
    }

    function _collectAffiliateAndBridgeFee(TxItem memory txItem, bytes memory from, uint256 toChain, bytes memory feeData, bool withCall)
    internal
    returns (uint256)
    {
        uint256 affiliateFee;
        if (feeData.length > 0) {
            // todo: send fee first or approve to affiliateFeeManager
            try affiliateFeeManager.collectAffiliatesFee(txItem.orderId, txItem.token, txItem.amount, feeData) returns (uint256 totalFee) {
                affiliateFee = totalFee;
                _sendToken(txItem.token, affiliateFee, address(affiliateFeeManager), true);

            } catch (bytes memory) {
                // do nothing
            }
        }

        uint256 amount = txItem.amount;
        (uint256 securityFee, uint256 vaultFee) =
                                _getRegistry().getTransferOutFee(from, txItem.token, txItem.amount,  txItem.chain, toChain, withCall);

        if (txItem.amount > affiliateFee + securityFee + vaultFee) {
            amount -= (affiliateFee + securityFee + vaultFee);
        } else if (txItem.amount > affiliateFee + securityFee) {
            vaultFee = txItem.amount - (affiliateFee + securityFee);
            amount = 0;
        } else if (txItem.amount > affiliateFee) {
            securityFee = txItem.amount - affiliateFee;
            vaultFee = 0;
            amount = 0;
        } else {
            securityFee = 0;
            vaultFee = 0;
            amount = 0;
        }

        vaultFeeInfos[txItem.token] += vaultFee;
        if (securityFee > 0) {
            _sendToken(txItem.token, securityFee, securityFeeReceiver, true);
        }

        emit BridgeFeeCollected(txItem.orderId, txItem.token, securityFee, vaultFee);

        return amount;
    }

    function _collectFromFee(TxItem memory txItem) internal view returns (uint256 outAmount) {
        uint256 proportionFee = _getRegistry().getTransferInFee(bytes(""), txItem.token, txItem.amount, txItem.chain);
        if (txItem.amount > proportionFee) {
            outAmount = txItem.amount - proportionFee;
        } else {
            proportionFee = txItem.amount;
            outAmount = 0;
        }
    }


    function _updateLastScanBlock(uint256 chain, uint64 height) internal {
        if (height > chainLastScanBlock[chain]) {
            chainLastScanBlock[chain] = height;
        }
    }

    function _migrate(TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault) internal {
        txItem.orderId = _getOrderId();

        BridgeItem memory bridgeItem;
        bridgeItem.vault = fromVault;
        bridgeItem.payload = toVault;
        bridgeItem.txType = TxType.MIGRATE;

        _emitRelay(selfChainId, bridgeItem, txItem, gasInfo);
    }

    // only support non-contract chain refund
    function _refund(BridgeItem memory bridgeItem, TxItem memory txItem) internal {
        GasInfo memory gasInfo;

        // refund from the from vault
        (txItem.amount, gasInfo) = vaultManager.refund(txItem, bridgeItem.vault);
        if (txItem.amount == 0) {
            // todo: emit complete?
            return;
        }

        bridgeItem.txType = TxType.REFUND;
        _emitRelay(txItem.chain, bridgeItem, txItem, gasInfo);
    }

    function _depositIn(
        bytes32 orderId,
        uint256 fromChain,
        address token,
        uint256 amount,
        bytes memory from,
        address receiver
    ) internal {
        address vaultToken = _getRegistry().getVaultToken(token);
        if (vaultToken == address(0)) revert Errs.vault_token_not_registered();
        IVaultToken(vaultToken).deposit(fromChain, amount, receiver);
        emit Deposit(orderId, fromChain, token, amount, receiver, from);
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
     * - bridgeItem must contain valid vault, from, to, and txType
     *
     * @param fromChain Source chain ID where the transaction originates
     * @param bridgeItem Bridge item containing vault and transaction details
     * @param txItem Transaction item with token and amount information
     * @param gasInfo Estimated gas required for the transaction on target chain
     */
    function _emitRelay(uint256 fromChain, BridgeItem memory bridgeItem, TxItem memory txItem, GasInfo memory gasInfo) internal {

        if (!(bridgeItem.txType == TxType.MIGRATE && txItem.chainType == ChainType.CONTRACT)) {
            // todo: amount + gas?
            // todo: burn when migration ?
            _checkAndBurn(txItem.token, txItem.amount);
            (bridgeItem.token, bridgeItem.amount) = _getToChainTokenAndAmount(txItem.chain, txItem.token, txItem.amount);
        }

        bridgeItem.chainAndGasLimit =
                        _getChainAndGasLimit(fromChain, txItem.chain, gasInfo.transactionRate, gasInfo.transactionSize);
        bridgeItem.sequence = ++chainSequence[txItem.chain];

        OrderInfo storage order = orderInfos[txItem.orderId];
        order.gasToken = txItem.token;
        order.estimateGas = gasInfo.estimateGas;

        order.hash = _getSignHash(txItem.orderId, bridgeItem.vault, bridgeItem);
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

    function _increaseVaultBalance(uint256 chain, address token, uint256 amount) internal {
        address vaultToken = _getRegistry().getVaultToken(token);
        IVaultToken(vaultToken).increaseVaultBalance(chain, amount);
    }

    function _reduceVaultBalance(uint256 chain, address token, uint256 amount) internal {
        address vaultToken = _getRegistry().getVaultToken(token);
        IVaultToken(vaultToken).reduceVaultBalance(chain, amount);
    }

    function _getRelayToken(uint256 chain, bytes memory token) internal view returns (address relayToken) {
        relayToken = _getRegistry().getRelayChainToken(chain, token);
    }

    function _getRelayAmount(uint256 chain, bytes memory token, uint256 fromAmount)
        internal
        view
        returns (uint256 relayAmount)
    {
        relayAmount = _getRegistry().getRelayChainAmount(token, chain, fromAmount);
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

    function _getToChainToken(uint256 chain, address relayToken) internal view returns (bytes memory token) {
        token = _getRegistry().getToChainToken(relayToken, chain);
    }

    function _getToChainAmount(uint256 chain, address token, uint256 relayAmount)
        internal
        view
        returns (uint256 amount)
    {
        amount = _getRegistry().getToChainAmount(token, relayAmount, chain);
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
