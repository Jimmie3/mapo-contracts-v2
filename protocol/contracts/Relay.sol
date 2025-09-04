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

import {TxType, TxInItem, TxOutItem, ChainType, TxItem} from "./libs/Types.sol";

import {Errs} from "./libs/Errors.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract Relay is BaseImplementation, ReentrancyGuardUpgradeable, IRelay {
    bytes32 private constant TOTAL_ALLOWANCE_VAULT_KEY = keccak256("total.allowance");

    uint256 public immutable selfChainId = block.chainid;

    uint256 private nonce;
    mapping(uint256 => uint256) private chainSequence;
    mapping(uint256 => uint256) private chainLastScanBlock;

    mapping(bytes32 => bool) private inOrderExecuted;
    mapping(bytes32 => bool) private outOrderExecuted;

    mapping(bytes32 => uint256) private txOutOrderGasEstimated;

    uint256 constant MINTABLE_TOKEN = 0x01;
    uint256 constant BRIDGABLE_TOKEN = 0x02;

    // token => feature
    mapping(address => uint256) public tokenFeatureList;

    IPeriphery public registry;

    IVaultManager public vaultManager;

    event ExecuteTxOut(TxOutItem txOutItem);
    event SetAddressRegistry(address _registry);

    event Withdraw(address token, address reicerver, uint256 vaultAmount, uint256 tokenAmount);

    event Deposit(bytes32 orderId, uint256 fromChain, address token, uint256 amount, address to);

    event TransferIn(bytes32 orderId, address token, uint256 amount, address to, bool result);

    event BridgeRelay(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txOutType,
        bytes vault,

        uint256 sequence,
        bytes token,
        uint256 amount,

        bytes from,
        bytes to,

        // tokenOut: bytes(payload)
        // migrate: bytes("vault")
        bytes data
    );

    event BridgeRelaySigned(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)
        uint256 indexed chainAndGasLimit,

        bytes vault,

        bytes relayData,         // abi.encode(chainAndGasLimit | txOutType | sequence | token | amount| from | to | data)
        bytes signature     // sign: encodePack(orderId | chainAndGasLimit | txOutType | sequence | bytes(token) | amount| bytes(from) | bytes(to) | bytes(data));
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

    function setAddressRegistry(address _registry) external restricted {
        require(_registry != address(0));
        registry = IPeriphery(_registry);
        emit SetAddressRegistry(_registry);
    }

    function rotate(bytes memory retiringVault, bytes memory activeVault) external override {
        _checkAccess(4);

        vaultManager.rotate(retiringVault, activeVault);
    }

    function migrate() external override returns (bool) {
        _checkAccess(4);

        (bool completed, uint256 toMigrateChain) = vaultManager.checkMigration();
        if (completed) {
            return true;
        }
        if (toMigrateChain == 0) {
            // no need do more migration, waiting for all migration completed
            return false;
        }

        uint256 gasFee;
        TxItem memory txItem;
        (gasFee, txItem.transactionRate, txItem.transactionSize) = _getTransferOutGas(false, toMigrateChain);

        bool toMigrate;
        bytes memory toVault;
        (toMigrate, txItem.vault, toVault, txItem.amount) = vaultManager.migrate(toMigrateChain, gasFee);
        if (toMigrate) {
            _migrate(txItem, toVault);
        }

        return false;
    }

    function addChain(uint256 chain, uint256 startBlock) external override {
        _checkAccess(3);
        _updateLastScanBlock(chain, startBlock);
    }

    function removeChain(uint256 chain) external override {
        _checkAccess(3);
        // todo: check vault migration
    }

    function deposit(address token, uint256 amount, address to) external {
        _receiveToken(token, amount, msg.sender);
        _deposit(bytes32(""), selfChainId, token, amount, to);
    }

    function withdraw(address _vaultToken, uint256 _vaultAmount) external whenNotPaused {
        address user = msg.sender;
        address token = IVaultToken(_vaultToken).getTokenAddress();
        address vaultToken = _getTokenRegister().getVaultToken(token);
        if (_vaultToken != vaultToken) revert Errs.invalid_vault_token();
        uint256 amount = IVaultToken(vaultToken).getTokenAmount(_vaultAmount);
        IVaultToken(vaultToken).withdraw(selfChainId, _vaultAmount, user);
        _sendToken(token, amount, user, false);
        emit Withdraw(token, user, _vaultAmount, amount);
    }

    function bridgeOut(address token, uint256 amount, uint256 toChain, bytes memory to, bytes memory payload)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (bytes32 orderId)
    {
        require(amount != 0);
        address user = msg.sender;
        require(toChain != selfChainId);

        _receiveToken(token, amount, user);

        TxItem memory txItem;
        txItem.orderId = _getOrderId();
        txItem.token = token;
        txItem.amount = amount;
        txItem.fromChain = selfChainId;
        txItem.toChain = toChain;
        txItem.to = to;

        (bytes memory affiliateData, bytes memory relayLoad, bytes memory targetLoad) =
            abi.decode(payload, (bytes, bytes, bytes));

        // todo: collect fee

        txItem.payload = targetLoad;

        uint256 gasFee;
        (gasFee, txItem.transactionRate, txItem.transactionSize) = _getTransferOutGas(payload.length > 0, toChain);

        bool success;
        (success, txItem.vault) = vaultManager.chooseVault(txItem.toChain, txItem.token, txItem.amount, gasFee);
        require(success);

        _emitRelay(TxType.TRANSFER, txItem);

        txOutOrderGasEstimated[orderId] = gasFee;

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

        IGasService gasService = IGasService(registry.getAddress(1));
        gasService.postNetworkFee(chain, height, transactionSize, transactionSizeWithCall, transactionRate);
    }

    function executeTxOut(TxOutItem calldata txOutItem) external override {
        if (outOrderExecuted[txOutItem.orderId]) revert Errs.order_executed();
        _checkAccess(4);
        _updateLastScanBlock(txOutItem.chain, txOutItem.height);

        //todo: send gas fee to sender

        // todo: mint saved gas

        if (txOutItem.txOutType == TxType.MIGRATE) {
            TxItem memory txItem;

            txItem.vault = txOutItem.vault;
            uint256 chain = txOutItem.chain;

            // todo: get target vault
            bytes memory targetVault;

            (bytes memory tokenBytes, uint256 amount) = abi.decode(txOutItem.data, (bytes, uint256));

            address token;

            uint256 gasEstimated = txOutOrderGasEstimated[txOutItem.orderId];

            vaultManager.migrationOut(txItem, targetVault, txOutItem.gasUsed, gasEstimated);
        } else {
            // process fee
        }

        emit ExecuteTxOut(txOutItem);
    }

    // payload |1byte affiliate count| n * 2 byte affiliateId + 2 byte fee rate| 2 byte relayOutToken|
    // 30 byte relayMinAmountOut| target call data|

    // swap: affiliate data | relay data | target data
    function executeTxIn(TxInItem memory txInItem) external override {
        if (inOrderExecuted[txInItem.orderId]) revert Errs.order_executed();
        _checkAccess(4);
        _updateLastScanBlock(txInItem.chain, txInItem.height);

        TxItem memory txItem;

        (txItem.token, txItem.amount) = _mintToken(txInItem.chain, txInItem.token, txInItem.amount);

        if (txInItem.txInType == TxType.DEPOSIT) {
            if (!vaultManager.transferIn(txInItem.chain, txInItem.vault, txItem.token, txItem.amount)) {
                // retired vault, refund token
                _refund();
            }
            _deposit(txInItem.orderId, txInItem.chain, txItem.token, txItem.amount, _fromBytes(txInItem.to));
        } else {
            (bytes memory affiliateData, bytes memory relayLoad, bytes memory targetLoad) =
                abi.decode(txInItem.data, (bytes, bytes, bytes));

            address toToken;
            uint256 toAmount;

            if (relayLoad.length > 0) {
                // todo: collect affiliate fee and transferIn fee
                _collectFee(affiliateData, false, txItem.token, txItem.amount);
                bool rst;
                (rst, txItem) = _swapOut(txItem.token, txItem.amount, txInItem.to, relayLoad, targetLoad);
                if (!rst) {
                    // refund
                    _refund(txInItem, toAmount, txInItem.from);
                }
            } else {
                /// todo: collect affiliate fee and transferIn fee
                _collectFee(affiliateData, true, txItem.token, txItem.amount);

                if (txInItem.toChain == selfChainId) {
                    _transferIn(txInItem.orderId, txItem.token, txItem.amount, _fromBytes(txInItem.to), targetLoad);
                } else {
                    _transferOut(txItem);
                }
            }
        }
    }

    function _swapOut(
        address _token,
        uint256 _amount,
        bytes memory _to,
        bytes memory _relayData,
        bytes memory _targetData
    ) internal returns (bool result, TxItem memory outItem) {
        address to = _fromBytes(_to);
        try this.swapOut(_token, _amount, to, _relayData, _targetData) returns (TxItem memory execOutItem) {
            outItem = execOutItem;
        } catch Error(string memory reason) {
            return (false, outItem);
        } catch (bytes memory reason) {
            return (false, outItem);
        }
        return (true, outItem);
    }

    function swapOut(
        address _to,
        address _token,
        uint256 _amount,
        uint256 _toChain,
        bytes memory _relayData,
        bytes memory _targetData
    ) external returns (TxItem memory outItem) {
        require(msg.sender == address(this));

        if (_amount > 0) _sendToken(_token, _to, _amount, false);

        (outItem.token, outItem.amount, outItem.to, outItem.payload) =
            IRelayExecutor(_to).relayExecute(_token, _amount, _relayData, _targetData);
        if (outItem.amount > 0) _receiveToken(outItem.token, outItem.amount, _to);

        uint256 gasFee;
        (gasFee, outItem.transactionRate, outItem.transactionSize) =
            _getTransferOutGas(outItem.payload.length > 0, _toChain);

        // todo: collect fee

        bool rst;
        (rst, outItem.vault) = vaultManager.chooseVault();
        if (!rst) {
            // no vault
            revert Errs.no_access();
        }

        outItem.amount -= gasFee;
    }

    function isOrderExecuted(bytes32 orderId, bool isTxIn) external view returns (bool executed) {
        executed = isTxIn ? inOrderExecuted[orderId] : outOrderExecuted[orderId];
    }

    function _updateLastScanBlock(uint256 chain, uint256 height) internal {
        chainLastScanBlock[chain] = height;
    }

    function _collectFee(bytes memory _affiliateData, bool _bridge, address _token, uint256 _amount)
        internal
        returns (uint256 amount)
    {
        // todo: collect affiliate fee

        if (_bridge) {
            // calculate rebalance fee
        }

        return amount;
    }

    function _migrate(TxItem memory txItem, bytes memory toVault) internal {
        // todo: set from and to
        txItem.orderId = _getOrderId();

        _emitRelay(TxType.MIGRATE, txItem);

        txOutOrderGasEstimated[txItem.orderId] = txItem.transactionSize * txItem.transactionRate;
    }

    // todo: how to detect the original sender, need refund address
    // only support non-contract chain refund
    function _refund(TxInItem memory txInItem, uint256 amount, bytes memory to) internal {
        (uint256 gasFee, uint256 transactionRate, uint256 transactionSize) = _getTransferOutGas(false, txInItem.chain);

        (bool result, bytes memory vault) = vaultManager.chooseVault(txInItem.chain, token, amount, gasFee);
        if (!result) {
            return;
        }

        vaultManager.transferOut();

        _emitRelay(TxType.REFUND, txItem);

        txOutOrderGasEstimated[txInItem.orderId] = gasFee;
    }

    function _transferOut(TxItem memory txItem) internal {
        bytes memory vault;
        uint256 transactionRate;
        uint256 transactionSize;

        uint256 gasFee;
        (gasFee, txItem.transactionRate, txItem.transactionSize) =
            _getTransferOutGas(txItem.payload.length > 0, txItem.toChain);

        bool success;
        (success, txItem.vault) = vaultManager.chooseVault(txItem.toChain, txItem.token, txItem.amount, gasFee);
        require(success);

        _emitRelay(TxType.TRANSFER, txItem);

        txOutOrderGasEstimated[txItem.orderId] = gasFee;
    }

    function _emitRelayOut(TxType txType, TxItem memory txItem) internal {
        uint256 chainAndGas =
            _getChainAndGas(txItem.fromChain, txItem.toChain, txItem.transactionRate, txItem.transactionSize);

        emit BridgeRelay(
            txItem.orderId,
            chainAndGas,
            txType,
            ++chainSequence[txItem.toChain],
            txItem.vault,
            txItem.from,
            txItem.to,
            abi.encode(txItem.amount, txItem.token, txItem.payload)
        );
    }

    function _transferIn(bytes32 orderId, address token, uint256 amount, address to, bytes memory payload) internal {
        bool result = _sendToken(token, amount, to, true);
        if (result && payload.length > 0 && to.code.length > 0) {
            try IReceiver(to).onReceived(orderId, token, amount, payload) {
                // success
            } catch {
                // handle failure
            }
        }
        emit TransferIn(orderId, token, amount, to, result);
    }

    function _deposit(bytes32 orderId, uint256 fromChain, address token, uint256 amount, address receiver) internal {
        address vaultToken = _getTokenRegister().getVaultToken(token);
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

    function _emitRelay(TxType txType, TxItem memory txItem) internal returns (bool) {
        bytes memory toChainToken = _getToChainToken(txItem.toChain, txItem.token);
        uint256 toChainAmount = _getToChainAmount(txItem.toChain, txItem.token, txItem.amount);

        _checkAndBurn(txItem.token, txItem.amount);

        uint256 chainAndGas =
            _getChainAndGas(txItem.fromChain, txItem.toChain, txItem.transactionRate, txItem.transactionSize);

        emit BridgeRelay(
            txItem.orderId,
            chainAndGas,
            txType,
            ++chainSequence[txItem.toChain],
            txItem.vault,
            txItem.from,
            txItem.to,
            abi.encode(txItem.amount, txItem.token, txItem.payload)
        );

        return (true);
    }

    function _getRelayToken(uint256 chain, bytes memory token) internal view returns (address relayToken) {
        relayToken = _getTokenRegister().getRelayChainToken(chain, token);
    }

    function _getNative() internal pure returns (bytes memory native) {
        return abi.encodePacked(address(0));
    }

    function _getTransferOutGas(bool withCall, uint256 chain)
        internal
        view
        returns (uint256 gasFee, uint256 transactionRate, uint256 transactionSize)
    {
        IGasService gasService = IGasService(registry.getAddress(1));
        uint256 transactionSizeWithCall;
        (transactionRate, transactionSize, transactionSizeWithCall) = gasService.getNetworkFeeInfo(chain);
        if (withCall) {
            transactionSize = transactionSizeWithCall;
        }
        gasFee = transactionSize * transactionRate;
    }

    function _getToChainToken(uint256 chain, address relayToken) internal view returns (bytes memory token) {
        token = _getTokenRegister().getToChainToken(relayToken, chain);
    }

    function _getRelayAmount(uint256 chain, bytes memory token, uint256 fromAmount)
        internal
        view
        returns (uint256 relayAmount)
    {
        relayAmount = _getTokenRegister().getRelayChainAmount(token, chain, fromAmount);
    }

    function _getToChainAmount(uint256 chain, address token, uint256 relayAmount)
        internal
        view
        returns (uint256 amount)
    {
        amount = _getTokenRegister().getToChainAmount(token, relayAmount, chain);
    }

    function _getOrderId() internal returns (bytes32 orderId) {
        return keccak256(abi.encodePacked(selfChainId, address(this), ++nonce));
    }

    function _getTokenRegister() internal view returns (IRegistry tokenRegister) {
        tokenRegister = IRegistry(registry.getAddress(3));
    }

    function _getChainAndGas(uint256 _fromChain, uint256 _toChain, uint256 _transactionRate, uint256 _transactionSize)
        internal
        pure
        returns (uint256 chainAndGas)
    {
        chainAndGas = ((_fromChain << 192) | (_toChain << 128) | (_transactionRate << 64) | _transactionSize);
    }

    function _checkAccess(uint256 t) internal view {
        if (msg.sender != registry.getAddress(t)) revert Errs.no_access();
    }

    function _fromBytes(bytes memory b) internal pure returns (address addr) {
        assembly {
            addr := mload(add(b, 20))
        }
    }
}
