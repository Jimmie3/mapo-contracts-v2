// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IReceiver} from "./interfaces/IReceiver.sol";
import {TxType, BridgeItem, TxItem} from "./libs/Types.sol";
import {IMintableToken} from "./interfaces/IMintableToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {Utils} from "./libs/Utils.sol";

import {BaseGateway} from "./base/BaseGateway.sol";

contract Gateway is BaseGateway {
    address public activeTssAddress;
    address public retireTssAddress;
    bytes public activeTss;
    bytes public retireTss;
    uint256 public retireSequence;

    event UpdateTSS(bytes32 orderId, bytes fromTss, bytes toTss);

    error order_executed();

    error invalid_signature();

    error invalid_target_chain();
    error invalid_vault();
    error invalid_in_tx_type();

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setTssAddress(bytes calldata _tss) external restricted {
        require(activeTss.length == 0 && _tss.length != 0);
        activeTss = _tss;
        activeTssAddress = Utils.getAddressFromPublicKey(_tss);
        emit UpdateTSS(bytes32(0), bytes(""), _tss);
    }

    function _deposit(bytes32 orderId, address outToken, uint256 amount, address from, address to, address refundAddr)
        internal
        override
    {
        bytes memory receiver = abi.encode(to);

        emit BridgeOut(
            orderId, selfChainId << 192, TxType.DEPOSIT, activeTss, outToken, amount, from, refundAddr, receiver, bytes("")
        );
    }

    function bridgeIn(address sender, bytes32 orderId, bytes calldata params, bytes calldata signature)
        external
        whenNotPaused
        nonReentrant
    {
        if (orderExecuted[orderId]) revert order_executed();

        TxItem memory txItem;

        BridgeItem memory bridgeItem = abi.decode(params, (BridgeItem));

        address vaultAddr = Utils.getAddressFromPublicKey(bridgeItem.vault);

        if (!_checkSignature(orderId, vaultAddr, signature, bridgeItem)) revert invalid_signature();

        address tssAddr = (bridgeItem.sequence > retireSequence) ? activeTssAddress : retireTssAddress;
        if (tssAddr != vaultAddr) revert invalid_vault();

        _checkTargetChain(bridgeItem.chainAndGasLimit);

        txItem.token = Utils.fromBytes(bridgeItem.token);
        txItem.to = Utils.fromBytes(bridgeItem.to);
        txItem.amount = bridgeItem.amount;

        emit BridgeIn(
            orderId,
            bridgeItem.chainAndGasLimit,
            bridgeItem.txType,
            bridgeItem.vault,
            bridgeItem.sequence,
            sender,
            txItem.token,
            txItem.amount,
            txItem.to,
            bridgeItem.payload
        );

        if (bridgeItem.txType == TxType.MIGRATE) {
            _updateTSS(orderId, bridgeItem.sequence, bridgeItem.payload);
        } else if (bridgeItem.txType == TxType.TRANSFER || bridgeItem.txType == TxType.REFUND) {
            _checkAndMint(txItem.token, txItem.amount);
            _bridgeTokenIn(orderId, bridgeItem, txItem);
        } else {
            revert invalid_in_tx_type();
        }
    }

    function _updateTSS(bytes32 orderId, uint256 sequence, bytes memory newVault) internal whenNotPaused nonReentrant {
        retireTss = activeTss;
        retireTssAddress = activeTssAddress;
        activeTss = newVault;
        retireSequence = sequence;
        activeTssAddress = Utils.getAddressFromPublicKey(newVault);

        emit UpdateTSS(orderId, retireTss, newVault);
    }

    function _checkSignature(
        bytes32 orderId,
        address vaultAddress,
        bytes calldata signature,
        BridgeItem memory params
    ) internal pure returns (bool) {
        bytes32 hash = _getSignHash(orderId, params);
        address signer = ECDSA.recover(hash, signature);
        return signer == vaultAddress;
    }

    function _checkTargetChain(uint256 chainAndGasLimit) internal view {
        uint256 toChain = (chainAndGasLimit >> 128) & 0xFFFFFFFFFFFFFFFF;
        if (toChain != selfChainId) revert invalid_target_chain();
    }

    function _getActiveVault() internal view override returns (bytes memory vault) {
        return activeTss;
    }
}
