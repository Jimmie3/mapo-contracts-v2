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

import {TxType, TxInItem, TxOutItem, ChainType, TxItem, BridgeItem} from "./libs/Types.sol";

import {Errs} from "./libs/Errors.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BaseGateway} from "./base/BaseGateway.sol";

contract Relay is BaseGateway, IRelay {
    mapping(uint256 => uint256) private chainSequence;
    mapping(uint256 => uint256) private chainLastScanBlock;

    mapping(bytes32 => bool) private outOrderExecuted;

    mapping(bytes32 => uint256) private orderIdToBlockNumber;

    IPeriphery public periphery;

    IVaultManager public vaultManager;

    IAffiliateFeeManager public affiliateFeeManager;

    ISwap public swap;

    struct Rate {
        uint64 rate;
        address receiver;
    }

    struct OrderInfo {
        bool signed;
        bytes32 hash;
        // address gasToken;
        uint256 estimateGas;
        uint256 balanceFee;
    }

    mapping(bytes32 => OrderInfo) public orderInfos;

    //id : 0 VToken  1:relayer
    mapping(bytes32 => Rate) public feeRate;

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
        // abi.encodePack(orderId, txType, vault, sequence, token, amount, from, to, data);
        bytes32 hash,
        bytes from,
        // tokenOut: bytes(payload)
        // migrate: bytes("vault")
        bytes data
    );

    // sign: encodePack(orderId | relayData);
    event BridgeRelaySigned( // abi.encode(chainAndGasLimit | txOutType | sequence | token | amount| from | to | data)
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,
        bytes vault,
        bytes relayData,
        bytes signature
    );

    event BridgeCompleted(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txOutType,
        bytes vault,
        uint256 sequence,
        address sender,
        bytes data
    );

    event BridgeFeeCollected(bytes32 indexed orderId, address token, uint256 amount);


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

    function rotate(bytes memory retiringVault, bytes memory activeVault) external override {
        _checkAccess(4);

        vaultManager.rotate(retiringVault, activeVault);
    }

    function migrate() external override returns (bool) {
        _checkAccess(4);

        TxItem memory txItem;
        BridgeItem memory bridgeItem;

        bool completed;
        (completed, txItem.chain) = vaultManager.checkMigration();
        if (completed) {
            return true;
        }
        if (txItem.chain == 0) {
            // no need do more migration, waiting for all migration completed
            return false;
        }

        uint256 gasEstimated;

        (gasEstimated, txItem.transactionRate, txItem.transactionSize) = _getTransferOutGas(false, txItem.chain);
        gasEstimated = _getRelayChainGasAmount(txItem.chain, gasEstimated);
        bool toMigrate;
        bytes memory toVault;
        (toMigrate, bridgeItem.vault, toVault, txItem.amount) = vaultManager.migrate(txItem.chain, gasEstimated);
        if (toMigrate) {
            _migrate(bridgeItem, txItem, toVault, gasEstimated);
        }

        return false;
    }

    function addChain(uint256 chain, uint256 startBlock) external override {
        _checkAccess(3);
        _updateLastScanBlock(chain, startBlock);
        vaultManager.addChain(chain);
    }

    function removeChain(uint256 chain) external override {
        _checkAccess(3);
        // todo: check vault migration
        (bool completed,) = vaultManager.checkMigration();
        if (!completed) revert Errs.migration_not_completed();
        vaultManager.removeChain(chain);
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
        _updateLastScanBlock(selfChainId, orderIdToBlockNumber[orderId]);
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

        ChainType chainType = _getRegistry().getChainType(chain);
        uint256 relayGasUsed = _getRelayChainGasAmount(chain, txOutItem.gasUsed);
        OrderInfo storage order = orderInfos[txOutItem.orderId];
        uint256 relayGasEstimated = order.estimateGas;
        if (chainType != ChainType.CONTRACT) {
            address gasToken = _getRegistry().getChainGasToken(chain);
            _checkAndBurn(gasToken, relayGasUsed);
            _reduceVaultBalance(chain, gasToken, relayGasUsed);
        } else {
            //todo: send gas fee to sender
        }
        if (bridgeItem.txType == TxType.MIGRATE) {
            if (chainType != ChainType.CONTRACT) {
                (txItem.token, txItem.amount) = _getRelayTokenAndAmount(chain, bridgeItem.token, bridgeItem.amount);
                // todo: mint token
                _checkAndMint(txItem.token, txItem.amount);
                // send gas to vault
            }
            vaultManager.migrationOut(txItem, bridgeItem.vault, bridgeItem.payload, relayGasUsed, relayGasEstimated);
        } else {
            (txItem.token, txItem.amount) = _getRelayTokenAndAmount(chain, bridgeItem.token, bridgeItem.amount);

            vaultManager.transferOut(
                txItem.chain, bridgeItem.vault, txItem.token, txItem.amount, relayGasUsed, relayGasEstimated
            );
        }
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

        _updateLastScanBlock(fromChain, txInItem.height);

        TxItem memory txItem;
        txItem.orderId = txInItem.orderId;
        (txItem.token, txItem.amount) = _getRelayTokenAndAmount(fromChain, bridgeItem.token, bridgeItem.amount);
        _checkAndMint(txItem.token, txItem.amount);
        txItem.chain = fromChain;
        // check vault, will refund if vault is retired
        if (!vaultManager.checkVault(fromChain, bridgeItem.vault)) {
            // refund
            bridgeItem.to = txInItem.refundAddr;
            bridgeItem.payload = bytes("");

            return _refund(bridgeItem, txItem, bridgeItem.vault);
        }

        if (!vaultManager.transferIn(txItem.chain, bridgeItem.vault, txItem.token, txItem.amount)) return;

        if (bridgeItem.txType == TxType.DEPOSIT) {
            _depositIn(
                txItem.orderId, txItem.chain, txItem.token, txItem.amount, bridgeItem.from, Utils.fromBytes(bridgeItem.to)
            );
        } else {
            _increaseVaultBalance(txItem.chain, txItem.token, txItem.amount);
            (bytes memory affiliateData, bytes memory relayLoad, bytes memory targetLoad) =
                abi.decode(bridgeItem.payload, (bytes, bytes, bytes));

            if (affiliateData.length > 0) {
                txItem.amount -= _collectAffiliateFee(txInItem.orderId, txItem.token, txItem.amount, affiliateData);
            }
            txItem.amount = _collectFromFee(txItem);
            if (txItem.amount == 0) return;

            txItem.chain = bridgeItem.chainAndGasLimit >> 128 & 0xFFFFFFFFFFFFFFFF;
            if (txItem.chain == selfChainId) {
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
                _reduceVaultBalance(txItem.chain, txItem.token, txItem.amount);
                return;
            }

            try this.execute(bridgeItem, txItem, fromChain, relayLoad, targetLoad) {}
            catch (bytes memory) {
                txItem.chain = fromChain;
                bridgeItem.to = txInItem.refundAddr;

                _refund(bridgeItem, txItem, bridgeItem.vault);  
            }
        }
    }

    function execute(BridgeItem memory bridgeItem, TxItem memory txItem, uint256 fromChain, bytes memory relayLoad, bytes memory targetLoad) public {
        if (relayLoad.length > 0) {
            (address tokenOut, uint256 amountOutMin) = abi.decode(relayLoad, (address, uint256));
            txItem.amount = swap.swap(txItem.token, txItem.amount, tokenOut, amountOutMin);
            txItem.token = tokenOut;
        }

        txItem.amount = _collectToChainFee(txItem, fromChain, targetLoad.length > 0);
        if (txItem.amount == 0) revert Errs.zero_amount_out();

        uint256 gasEstimated;
        (gasEstimated, txItem.transactionRate, txItem.transactionSize) =
            _getTransferOutGas(targetLoad.length > 0, txItem.chain);
        gasEstimated = _getRelayChainGasAmount(txItem.chain, gasEstimated);

        (bridgeItem.vault) = vaultManager.chooseVault(txItem.chain, txItem.token, txItem.amount, gasEstimated);
        if (bridgeItem.vault.length == 0) revert Errs.invalid_vault();

        vaultManager.doTransfer(txItem.chain, bridgeItem.vault, txItem.token, txItem.amount, gasEstimated);
        bridgeItem.payload = targetLoad;

        bridgeItem.txType = TxType.TRANSFER;

        _emitRelay(fromChain, bridgeItem, txItem, gasEstimated);
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

        (bytes memory affiliateData, bytes memory relayLoad, bytes memory targetLoad) =
            abi.decode(payload, (bytes, bytes, bytes));

        if(affiliateData.length > 0) {
            txItem.amount -= _collectAffiliateFee(txItem.orderId, txItem.token, txItem.amount, affiliateData);
        }

        execute(bridgeItem, txItem, selfChainId, relayLoad, targetLoad);
    }

    function _collectToChainFee(TxItem memory txItem, uint256 fromChain, bool withCall)
        internal
        returns (uint256 outAmount)
    {
        uint256 proportionFee;
        uint256 baseFee;
        (, baseFee, proportionFee) =
            _getRegistry().getTransferOutFee(bytes(""), txItem.token, txItem.amount, fromChain, txItem.chain, withCall);
        if (txItem.amount > baseFee + proportionFee) {
            outAmount = txItem.amount - baseFee - proportionFee;
        } else if (txItem.amount >= baseFee) {
            proportionFee = txItem.amount - baseFee;
        } else {
            baseFee = txItem.amount;
            proportionFee = 0;
        }
    }

    function _collectAffiliateFee(bytes32 orderId, address token, uint256 amount, bytes memory feeData)
        internal
        returns (uint256 fee)
    {
        // todo: send fee first or approve to affiliateFeeManager
        try affiliateFeeManager.collectAffiliatesFee(orderId, token, amount, feeData) returns (uint256 totalFee) {
            _sendToken(token, amount, address(affiliateFeeManager), true);
            fee = totalFee;
        } catch (bytes memory) {
            // do nothing
        }
    }

    function _collectFromFee(TxItem memory txItem) internal returns (uint256 outAmount) {
        uint256 proportionFee = _getRegistry().getTransferInFee(bytes(""), txItem.token, txItem.amount, txItem.chain);
        if (txItem.amount > proportionFee) {
            outAmount = txItem.amount - proportionFee;
        } else {
            proportionFee = txItem.amount;
            outAmount = 0;
        }
    }

    function isOrderExecuted(bytes32 orderId, bool isTxIn) external view override returns (bool executed) {
        executed = isTxIn ? orderExecuted[orderId] : outOrderExecuted[orderId];
    }

    function getChainLastScanBlock(uint256 chain) external view override returns(uint256) {
        return chainLastScanBlock[chain];
    }

    function _updateLastScanBlock(uint256 chain, uint256 height) internal {
        if (height > chainLastScanBlock[chain]) {
            chainLastScanBlock[chain] = height;
        }
    }

    function _migrate(BridgeItem memory bridgeItem, TxItem memory txItem, bytes memory toVault, uint256 gasEstimated) internal {
        txItem.orderId = _getOrderId();

        if (_getRegistry().getChainType(txItem.chain) != ChainType.CONTRACT) {
            txItem.token = _getRegistry().getChainGasToken(txItem.chain);
        }
        bridgeItem.payload = toVault;
        bridgeItem.txType = TxType.MIGRATE;

        _emitRelay(selfChainId, bridgeItem, txItem, gasEstimated);
    }

    // todo: how to detect the original sender, need refund address
    // only support non-contract chain refund
    function _refund(BridgeItem memory bridgeItem, TxItem memory txItem, bytes memory vault) internal {
        uint256 gasEstimated;
        (gasEstimated, txItem.transactionRate, txItem.transactionSize) = _getTransferOutGas(false, txItem.chain);
        gasEstimated = _getRelayChainGasAmount(txItem.chain, gasEstimated);

        // refund from the from vault
        vaultManager.doTransfer(txItem.chain, vault, txItem.token, txItem.amount, gasEstimated);

        bridgeItem.txType = TxType.REFUND;
        _emitRelay(txItem.chain, bridgeItem, txItem, gasEstimated);
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

    // function _receiveToken(address token, uint256 amount, address from) internal {
    //     (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, address(this), amount));
    //     if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
    //         revert Errs.transfer_token_in_failed();
    //     }
    // }

    function _emitRelay(uint256 fromChain, BridgeItem memory bridgeItem, TxItem memory txItem, uint256 gasEstimated) internal {
        if (!(bridgeItem.txType == TxType.MIGRATE && _getRegistry().getChainType(txItem.chain) == ChainType.CONTRACT)) {
            _checkAndBurn(txItem.token, txItem.amount);
            (bridgeItem.token, bridgeItem.amount) = _getToChainTokenAndAmount(txItem.chain, txItem.token, txItem.amount);
        }

        bridgeItem.chainAndGasLimit =
                        _getChainAndGas(fromChain, txItem.chain, txItem.transactionRate, txItem.transactionSize);
        bridgeItem.sequence = ++chainSequence[txItem.chain];

        OrderInfo storage order = orderInfos[txItem.orderId];
        order.estimateGas = gasEstimated;

        order.hash = _getSignHash(txItem.orderId, bridgeItem.vault, bridgeItem);
        orderIdToBlockNumber[txItem.orderId] = block.number;
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


    function _getTransferOutGas(bool withCall, uint256 chain)
    internal
    view
    returns (uint256 gasFee, uint256 transactionRate, uint256 transactionSize)
    {
        IGasService gasService = IGasService(periphery.getAddress(1));
        uint256 transactionSizeWithCall;
        (transactionRate, transactionSize, transactionSizeWithCall) = gasService.getNetworkFeeInfo(chain);
        if (withCall) {
            transactionSize = transactionSizeWithCall;
        }
        gasFee = transactionSize * transactionRate;
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

    function _getChainAndGas(uint256 _fromChain, uint256 _toChain, uint256 _transactionRate, uint256 _transactionSize)
        internal
        pure
        returns (uint256 chainAndGas)
    {
        chainAndGas = ((_fromChain << 192) | (_toChain << 128) | (_transactionRate << 64) | _transactionSize);
    }



    function _checkAccess(uint256 t) internal view {
        if (msg.sender != periphery.getAddress(t)) revert Errs.no_access();
    }
}
