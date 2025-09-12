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
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IVaultManager} from "./interfaces/IVaultManager.sol";
import {ISwap} from "./interfaces/ISwap.sol";
import {IAffiliateFeeManager} from "./interfaces/IAffiliateFeeManager.sol";

import {TxType, TxInItem, TxOutItem, ChainType, TxItem} from "./libs/Types.sol";

import {Errs} from "./libs/Errors.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract Relay is BaseImplementation, ReentrancyGuardUpgradeable, IRelay {
    uint256 constant MINTABLE_TOKEN = 0x02;
    uint256 constant BRIDGABLE_TOKEN = 0x01;

    uint256 public immutable selfChainId = block.chainid;

    uint256 private nonce;
    mapping(uint256 => uint256) private chainSequence;
    mapping(uint256 => uint256) private chainLastScanBlock;

    mapping(bytes32 => bool) private inOrderExecuted;
    mapping(bytes32 => bool) private outOrderExecuted;

    mapping(bytes32 => uint256) private txOutOrderGasEstimated;
    mapping(bytes32 => uint256) private orderIdToBlockNumber;

    // token => feature
    mapping(address => uint256) public tokenFeatureList;

    IPeriphery public periphery;

    IVaultManager public vaultManager;

    IAffiliateFeeManager public affiliateFeeManager;

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

    ISwap public swap;

    // event ExecuteTxOut(TxOutItem txOutItem);
    event SetPeriphery(address _periphery);
    event UpdateTokens(address token, uint256 feature);
    event Withdraw(address token, address reicerver, uint256 vaultAmount, uint256 tokenAmount);

    event Deposit(bytes32 orderId, uint256 fromChain, address token, uint256 amount, address to);

    event TransferIn(bytes32 orderId, address token, uint256 amount, address to, bool result);

    event BridgeRelay( // abi.encodePack(orderId, txType, vault, sequence, token, amount, from, to, data);
        // tss sign base on this hash
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txType,
        bytes vault,
        uint256 sequence,
        bytes32 hash,
        bytes token,
        uint256 amount,
        bytes from,
        bytes to,
        // tokenOut: bytes(payload)
        // migrate: bytes("vault")
        bytes data
    );

    event BridgeRelaySigned( // abi.encode(chainAndGasLimit | txOutType | sequence | token | amount| from | to | data)
        // sign: encodePack(orderId | relayData);
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

    event BridgeIn( // maintainer, will receive gas on relay chain
        // migration: new vault
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | reserved (8 bytes) | gasUsed (8 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txInType,
        bytes vault,
        uint256 sequence,
        address sender,
        address token,
        uint256 amount,
        bytes from,
        address to,
        bytes data
    );

    event BridgeFeeCollected(bytes32 indexed orderId, address token, uint256 amount);

    function setPeriphery(address _periphery) external restricted {
        require(_periphery != address(0));
        periphery = IPeriphery(_periphery);
        emit SetPeriphery(_periphery);
    }

    function updateTokens(address[] calldata _tokens, uint256 _feature) external restricted {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenFeatureList[_tokens[i]] = _feature;
            emit UpdateTokens(_tokens[i], _feature);
        }
    }

    function rotate(bytes memory retiringVault, bytes memory activeVault) external override {
        _checkAccess(4);

        vaultManager.rotate(retiringVault, activeVault);
    }

    function migrate() external override returns (bool) {
        _checkAccess(4);

        TxItem memory txItem;
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
        (toMigrate, txItem.vault, toVault, txItem.amount) = vaultManager.migrate(txItem.chain, gasEstimated);
        if (toMigrate) {
            _migrate(txItem, toVault, gasEstimated);
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

    function deposit(address token, uint256 amount, address to) external {
        _receiveToken(token, amount, msg.sender);
        _deposit(bytes32(""), selfChainId, token, amount, to);
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

    function relaySigned(
        bytes32 orderId,
        uint256 chainAndGasLimit,
        bytes calldata vault,
        bytes calldata relayData,
        bytes calldata signature
    ) external {
        uint256 last = orderIdToBlockNumber[orderId];
        OrderInfo storage order = orderInfos[orderId];
        if (order.signed) return;

        bytes32 vaultKey = keccak256(vault);
        // if (vaultKey != order.vaultKey) revert Errs.invalid_vault();

        // todo: check the hash in bridgeRelay

        if (!_checkSignature(orderId, vault, relayData, signature)) revert Errs.invalid_signature();
        // if(!vaultManager.checkVault(vault)) revert Errs.invalid_vault();

        order.signed = true;
        _updateLastScanBlock(selfChainId, last);

        emit BridgeRelaySigned(orderId, chainAndGasLimit, vault, relayData, signature);
    }

    function bridgeOut(address token, uint256 amount, uint256 toChain, bytes memory to, bytes memory payload)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (bytes32 orderId)
    {
        require((amount != 0) && (toChain != selfChainId));
        address user = msg.sender;
        _receiveToken(token, amount, user);

        TxItem memory txItem;
        txItem.orderId = _getOrderId();
        txItem.token = token;
        txItem.amount = amount;
        txItem.chain = toChain;
        txItem.to = to;

        (bytes memory affiliateData, bytes memory relayLoad, bytes memory targetLoad) =
            abi.decode(payload, (bytes, bytes, bytes));

        txItem.amount -= _collectAffiliateFee(txItem.orderId, txItem.token, txItem.amount, affiliateData);
        execute(txItem, selfChainId, relayLoad, targetLoad);

        return txItem.orderId;
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
        uint256 chain = (txOutItem.chainAndGasLimit >> 128) & (1 << 64 - 1);
        _updateLastScanBlock(chain, txOutItem.height);

        TxItem memory txItem;
        txItem.orderId = txOutItem.orderId;
        txItem.vault = txOutItem.vault;
        txItem.chain = chain;
        ChainType chainType = _getRegistry().getChainType(txItem.chain);
        uint256 relayGasUsed = _getRelayChainGasAmount(txItem.chain, txOutItem.gasUsed);
        uint256 relayGasEstimated = txOutOrderGasEstimated[txOutItem.orderId];
        if (chainType != ChainType.CONTRACT) {
            _reduceVaultBalance(chain, _getRegistry().getChainGasToken(chain), relayGasUsed);
            // todo: send gas fee to tss
        } else {
            //todo: send gas fee to sender
        }
        if (txOutItem.txOutType == TxType.MIGRATE) {
            if (chainType != ChainType.CONTRACT) {
                txItem.token = _getRelayToken(txItem.chain, txOutItem.token);
                txItem.amount = _getRelayAmount(txItem.chain, txOutItem.token, txOutItem.amount);
                // todo: mint token
                // send gas to vault
            }
            vaultManager.migrationOut(txItem, txOutItem.data, relayGasUsed, relayGasEstimated);
        } else {
            txItem.amount = _getRelayAmount(txItem.chain, txOutItem.token, txOutItem.amount);
            txItem.token = _getRelayToken(txItem.chain, txOutItem.token);
            vaultManager.transferOut(
                txItem.chain, txItem.vault, txItem.token, txItem.amount, relayGasUsed, relayGasEstimated
            );
        }
        emit BridgeCompleted(
            txOutItem.orderId,
            txOutItem.chainAndGasLimit,
            txOutItem.txOutType,
            txOutItem.vault,
            txOutItem.sequence,
            txOutItem.sender,
            txOutItem.data
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
        if (inOrderExecuted[txInItem.orderId]) revert Errs.order_executed();

        _checkAccess(4);

        uint256 fromChain = txInItem.chainAndGasLimit >> 192;

        _updateLastScanBlock(fromChain, txInItem.height);

        TxItem memory txItem;
        txItem.orderId = txInItem.orderId;
        txItem.from = txInItem.from;

        (txItem.token, txItem.amount) = _mintToken(fromChain, txInItem.token, txInItem.amount);

        // check vault, will refund if vault is retired
        if (!vaultManager.checkVault(fromChain, txInItem.vault)) {
            // refund
            txItem.chain = fromChain;
            txItem.to = txInItem.refundAddr;
            txItem.vault = txItem.vault;

            return _refund(txItem);
        }

        txItem.to = txInItem.to;

        if (!vaultManager.transferIn(txItem.chain, txInItem.vault, txItem.token, txItem.amount)) return;

        if (txInItem.txInType == TxType.DEPOSIT) {
            _deposit(txItem.orderId, txItem.chain, txItem.token, txItem.amount, _fromBytes(txItem.to));
        } else {
            _increaseVaultBalance(txItem.chain, txItem.token, txItem.amount);
            (bytes memory affiliateData, bytes memory relayLoad, bytes memory targetLoad) =
                abi.decode(txInItem.payload, (bytes, bytes, bytes));

            if (affiliateData.length > 0) {
                txItem.amount -= _collectAffiliateFee(txInItem.orderId, txItem.token, txItem.amount, affiliateData);
            }
            txItem.amount = _collectFromFee(txItem);
            if (txItem.amount == 0) return;

            txItem.chain = txInItem.chainAndGasLimit >> 128 & 0xFFFFFFFFFFFFFFFF;
            if (txItem.chain == selfChainId) {
                _transferIn(txItem, txInItem.txInType, txInItem.chainAndGasLimit, targetLoad);
                _reduceVaultBalance(txItem.chain, txItem.token, txItem.amount);
                return;
            }

            try this.execute(txItem, fromChain, relayLoad, targetLoad) {}
            catch (bytes memory) {
                txItem.chain = fromChain;
                txItem.to = txInItem.refundAddr;
                txItem.vault = txItem.vault;

                _refund(txItem);
            }
        }
    }

    function execute(TxItem memory txItem, uint256 fromChain, bytes memory relayLoad, bytes memory targetLoad) public {
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

        (txItem.vault) = vaultManager.chooseVault(txItem.chain, txItem.token, txItem.amount, gasEstimated);
        if (txItem.vault.length == 0) revert Errs.invalid_vault();

        vaultManager.doTransfer(txItem.chain, txItem.vault, txItem.token, txItem.amount, gasEstimated);
        txItem.payload = targetLoad;

        _emitRelay(TxType.TRANSFER, fromChain, txItem, gasEstimated);
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

    function isOrderExecuted(bytes32 orderId, bool isTxIn) external view returns (bool executed) {
        executed = isTxIn ? inOrderExecuted[orderId] : outOrderExecuted[orderId];
    }

    function _updateLastScanBlock(uint256 chain, uint256 height) internal {
        if (height > chainLastScanBlock[chain]) {
            chainLastScanBlock[chain] = height;
        }
    }

    function _migrate(TxItem memory txItem, bytes memory toVault, uint256 gasEstimated) internal {
        txItem.orderId = _getOrderId();

        if (_getRegistry().getChainType(txItem.chain) != ChainType.CONTRACT) {
            txItem.token = _getRegistry().getChainGasToken(txItem.chain);
        }
        txItem.payload = toVault;
        _emitRelay(TxType.MIGRATE, selfChainId, txItem, gasEstimated);
    }

    // todo: how to detect the original sender, need refund address
    // only support non-contract chain refund
    function _refund(TxItem memory txItem) internal {
        uint256 gasEstimated;
        (gasEstimated, txItem.transactionRate, txItem.transactionSize) = _getTransferOutGas(false, txItem.chain);
        gasEstimated = _getRelayChainGasAmount(txItem.chain, gasEstimated);

        // refund from the from vault
        vaultManager.doTransfer(txItem.chain, txItem.vault, txItem.token, txItem.amount, gasEstimated);
        _emitRelay(TxType.REFUND, txItem.chain, txItem, gasEstimated);
    }

    function _transferIn(TxItem memory txItem, TxType txType, uint256 chainAndGasLimit, bytes memory targetLoad)
        internal
    {
        address to = _fromBytes(txItem.to);
        bool result = _sendToken(txItem.token, txItem.amount, to, true);
        if (result && targetLoad.length > 0 && to.code.length > 0) {
            try IReceiver(to).onReceived(
                txItem.orderId, txItem.token, txItem.amount, txItem.chain, txItem.from, targetLoad
            ) {
                // success
            } catch {
                // handle failure
            }
        }
        emit BridgeIn(
            txItem.orderId,
            chainAndGasLimit,
            txType,
            txItem.vault,
            0,
            msg.sender,
            txItem.token,
            txItem.amount,
            txItem.from,
            to,
            targetLoad
        );
    }

    function _deposit(bytes32 orderId, uint256 fromChain, address token, uint256 amount, address receiver) internal {
        address vaultToken = _getRegistry().getVaultToken(token);
        if (vaultToken == address(0)) revert Errs.vault_token_not_registered();
        IVaultToken(vaultToken).deposit(fromChain, amount, receiver);
        emit Deposit(orderId, fromChain, token, amount, receiver);
    }

    function _mintToken(uint256 fromChain, bytes memory token, uint256 amount)
        internal
        returns (address relayToken, uint256 relayAmount)
    {
        relayToken = _getRelayToken(fromChain, token);
        relayAmount = _getRelayAmount(fromChain, token, amount);
        _checkAndMint(relayToken, relayAmount);
    }

    function _checkAndBurn(address _token, uint256 _amount) internal {
        if (_isMintable(_token)) {
            // todo: check burn or burnFrom
            IMintableToken(_token).burn(_amount);
        }
    }

    function _checkAndMint(address _token, uint256 _amount) internal {
        if (_isMintable(_token)) {
            IMintableToken(_token).mint(address(this), _amount);
        }
    }

    function _isMintable(address _token) internal view returns (bool) {
        return (tokenFeatureList[_token] & MINTABLE_TOKEN) == MINTABLE_TOKEN;
    }

    function _sendToken(address token, uint256 amount, address to, bool handle) internal returns (bool result) {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        result = (success && (data.length == 0 || abi.decode(data, (bool))));
        if (!handle && !result) revert Errs.transfer_token_out_failed();
    }

    function _receiveToken(address token, uint256 amount, address from) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, address(this), amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert Errs.transfer_token_in_failed();
        }
    }

    function _emitRelay(TxType txType, uint256 fromChain, TxItem memory txItem, uint256 gasEstimated) internal {
        bytes memory toChainToken;
        uint256 toChainAmount;
        if (!(txType == TxType.MIGRATE && _getRegistry().getChainType(txItem.chain) == ChainType.CONTRACT)) {
            _checkAndBurn(txItem.token, txItem.amount);
            toChainToken = _getToChainToken(txItem.chain, txItem.token);
            toChainAmount = _getToChainAmount(txItem.chain, txItem.token, txItem.amount);
        }

        OrderInfo storage order = orderInfos[txItem.orderId];
        order.estimateGas = gasEstimated;

        uint256 chainAndGas = _getChainAndGas(fromChain, txItem.chain, txItem.transactionRate, txItem.transactionSize);

        // todo: save signed hash
        uint256 sequence = ++chainSequence[txItem.chain];
        order.hash = keccak256(
            abi.encodePacked(
                txItem.orderId,
                chainAndGas,
                txType,
                txItem.vault,
                sequence,
                toChainToken,
                toChainAmount,
                txItem.from,
                txItem.to,
                txItem.payload
            )
        );

        emit BridgeRelay(
            txItem.orderId,
            chainAndGas,
            txType,
            txItem.vault,
            sequence,
            order.hash,
            toChainToken,
            toChainAmount,
            txItem.from,
            txItem.to,
            txItem.payload
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

    function _getToChainToken(uint256 chain, address relayToken) internal view returns (bytes memory token) {
        token = _getRegistry().getToChainToken(relayToken, chain);
    }

    function _getRelayAmount(uint256 chain, bytes memory token, uint256 fromAmount)
        internal
        view
        returns (uint256 relayAmount)
    {
        relayAmount = _getRegistry().getRelayChainAmount(token, chain, fromAmount);
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

    function _checkSignature(bytes32 orderId, bytes calldata vault, bytes calldata relayData, bytes calldata signature)
        internal
        pure
        returns (bool)
    {
        bytes32 hash = keccak256(abi.encodePacked(orderId, relayData));
        address signer = ECDSA.recover(hash, signature);
        return signer == _publicKeyToAddress(vault);
    }

    function _publicKeyToAddress(bytes calldata publicKey) public pure returns (address) {
        return address(uint160(uint256(keccak256(publicKey))));
    }

    function _checkAccess(uint256 t) internal view {
        if (msg.sender != periphery.getAddress(t)) revert Errs.no_access();
    }

    function _fromBytes(bytes memory b) internal pure returns (address addr) {
        assembly {
            addr := mload(add(b, 20))
        }
    }
}
