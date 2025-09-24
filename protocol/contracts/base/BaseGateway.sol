// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGateway} from "../interfaces/IGateWay.sol";

import {IReceiver} from "../interfaces/IReceiver.sol";
import {IMintableToken} from "../interfaces/IMintableToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

import {TxType, BridgeItem, TxItem} from "../libs/Types.sol";
import {Utils} from "../libs/Utils.sol";

abstract contract BaseGateway is IGateway, BaseImplementation, ReentrancyGuardUpgradeable {
    address internal constant ZERO_ADDRESS = address(0);
    uint256 internal constant MIN_GAS_FOR_LOG = 20_000;

    uint256 constant MINTABLE_TOKEN = 0x02;
    uint256 constant BRIDGEABLE_TOKEN = 0x01;

    uint256 public immutable selfChainId = block.chainid;

    uint256 internal nonce;

    address public wToken;

    mapping(bytes32 => bool) internal orderExecuted;

    // token => feature
    mapping(address => uint256) public tokenFeatureList;

    mapping(bytes32 => bool) public failedHash;

    event SetWToken(address _wToken);
    event UpdateTokens(address token, uint256 feature);

    event BridgeOut(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | reserved (16 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txOutType,
        bytes vault,
        address token,
        uint256 amount,
        address from,
        address refundAddr,
        bytes to,
        bytes payload
    );

    event BridgeIn(
        bytes32 indexed orderId,
        // fromChain (8 bytes) | toChain (8 bytes) | reserved (8 bytes) | gasUsed (8 bytes)
        uint256 indexed chainAndGasLimit,
        TxType txInType,
        bytes vault,
        uint256 sequence,
        address sender,  // maintainer, will receive gas on relay chain
        address token,
        uint256 amount,
        //bytes from,
        address to,
        bytes data      // migration: new vault
    );

    event BridgeFailed(
        bytes32 indexed orderId, address token, uint256 amount, bytes from, address to, bytes data, bytes reason
    );

    error transfer_in_failed();
    error transfer_out_failed();

    error zero_address();
    error invalid_refund_address();
    error not_bridge_able();

    function setWtoken(address _wToken) external restricted {
        require(_wToken != ZERO_ADDRESS);
        wToken = _wToken;
        emit SetWToken(_wToken);
    }

    function updateTokens(address[] calldata _tokens, uint256 _feature) external restricted {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenFeatureList[_tokens[i]] = _feature;
            emit UpdateTokens(_tokens[i], _feature);
        }
    }

    function deposit(address token, uint256 amount, address to, address refundAddr)
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (bytes32 orderId)
    {
        require(amount != 0);
        address user = msg.sender;
        if (to == ZERO_ADDRESS) revert zero_address();
        if (refundAddr == ZERO_ADDRESS) revert invalid_refund_address();

        address outToken = _safeReceiveToken(token, user, amount);
        orderId = _getOrderId(user);

        _deposit(orderId, outToken, amount, user, to, refundAddr);

        return orderId;
    }

    function isOrderExecuted(bytes32 orderId, bool) external view virtual returns (bool) {
        return orderExecuted[orderId];
    }

    function isMintable(address _token) external view returns (bool) {
        return _isMintable(_token);
    }

    function isBridgeable(address _token) external view returns (bool) {
        return _isBridgeable(_token);
    }

    function _deposit(bytes32 orderId, address token, uint256 amount, address from, address to, address refundAddr)
        internal
        virtual;

    function bridgeOut(
        address token,
        uint256 amount,
        uint256 toChain,
        bytes memory to,
        address refundAddr,
        bytes memory payload
    ) external payable override whenNotPaused nonReentrant returns (bytes32 orderId) {
        require(amount != 0 && toChain != selfChainId);
        if (refundAddr == ZERO_ADDRESS) revert invalid_refund_address();

        address user = msg.sender;
        address outToken = _safeReceiveToken(token, user, amount);
        if (!_isBridgeable(outToken)) revert not_bridge_able();

        // address from = (refund == address(0)) ? user : refund;
        uint256 chainAndGasLimit = selfChainId << 192 | toChain << 128;

        emit BridgeOut(
            orderId,
            chainAndGasLimit,
            TxType.TRANSFER,
            _getActiveVault(),
            outToken,
            amount,
            user,
            refundAddr,
            to,
            payload
        );

        _bridgeOut(orderId, outToken, amount, toChain, to, payload);

        return orderId;
    }

    function _getActiveVault() internal view virtual returns (bytes memory vault);

    function _bridgeOut(
        bytes32 orderId,
        address token,
        uint256 amount,
        uint256 toChain,
        bytes memory to,
        bytes memory payload
    ) internal virtual {}

    function _bridgeTokenIn(bytes32 orderId, BridgeItem memory bridgeItem, TxItem memory txItem) internal {

        if (txItem.amount > 0 && txItem.to != address(0)) {
            bool needCall = _needCall(txItem.to, bridgeItem.payload.length);
            bool result = _safeTransferOut(txItem.token, txItem.to, txItem.amount, needCall);
            if (result && needCall) {
                uint256 fromChain = bridgeItem.chainAndGasLimit >> 192;
                uint256 gasForCall = gasleft() - MIN_GAS_FOR_LOG;
                try IReceiver(txItem.to).onReceived{gas: gasForCall}(
                    orderId, txItem.token, txItem.amount, fromChain, bridgeItem.from, bridgeItem.payload
                ) {} catch {}

                return;
            }
        }

        _bridgeFailed(orderId, bridgeItem,  txItem, bytes("transferFailed"));
    }

    function _bridgeFailed(bytes32 orderId, BridgeItem memory param, TxItem memory baseItem, bytes memory reason) internal {
        bytes32 hash =
            keccak256(abi.encodePacked(orderId, baseItem.token, baseItem.amount, param.from, baseItem.to, param.payload));
        failedHash[hash] = true;
        emit BridgeFailed(orderId, baseItem.token, baseItem.amount, param.from, baseItem.to, param.payload, reason);
    }

    function _safeTransferOut(address token, address to, uint256 value, bool needCall) internal returns (bool result) {
        address _wToken = wToken;
        if (token == _wToken && !needCall) {
            bool success;
            bytes memory data;
            // unwrap wToken
            (success, data) = _wToken.call(abi.encodeWithSelector(0x2e1a7d4d, value));
            result = (success && (data.length == 0 || abi.decode(data, (bool))));
            if (result) {
                // transfer native token to the recipient
                (success, data) = to.call{value: value}("");
            } else {
                // if unwrap failed, fallback to transfer wToken
                (success, data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
            }
            result = (success && (data.length == 0 || abi.decode(data, (bool))));
        } else {
            // bytes4(keccak256(bytes('transfer(address,uint256)')));  transfer
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
            result = (success && (data.length == 0 || abi.decode(data, (bool))));
        }
    }

    function _safeReceiveToken(address token, address from, uint256 value) internal returns (address outToken) {
        address to = address(this);
        if (token == ZERO_ADDRESS) {
            outToken = wToken;
            if (msg.value != value) revert transfer_in_failed();
            // wrap native token
            (bool success, bytes memory data) = outToken.call{value: value}(abi.encodeWithSelector(0xd0e30db0));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert transfer_in_failed();
            }
        } else {
            outToken = token;
            uint256 balanceBefore = IERC20(token).balanceOf(to);
            // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));  transferFrom
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert transfer_in_failed();
            }
            uint256 balanceAfter = IERC20(token).balanceOf(to);
            if (balanceAfter - balanceBefore != value) revert transfer_in_failed();

            _checkAndBurn(outToken, value);
        }
    }

    function _getOrderId(address user) internal returns (bytes32 orderId) {
        return keccak256(abi.encodePacked(address(this), selfChainId, user, ++nonce));
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

    function _getSignHash(bytes32 orderId, bytes memory vault, BridgeItem memory bridgeItem)
    internal
    pure
    returns (bytes32)
    {
        // payload length might be long
        // use payload hash to optimize the encodePacked gas
        bytes32 payloadHash = keccak256(bridgeItem.payload);
        bytes32 hash = keccak256(
            abi.encodePacked(
                orderId,
                bridgeItem.chainAndGasLimit,
                bridgeItem.txType,
                vault,
                bridgeItem.sequence,
                bridgeItem.token,
                bridgeItem.amount,
                bridgeItem.from,
                bridgeItem.to,
                payloadHash
            )
        );

        return hash;
    }

    function _isMintable(address _token) internal view returns (bool) {
        return (tokenFeatureList[_token] & MINTABLE_TOKEN) == MINTABLE_TOKEN;
    }

    function _isBridgeable(address _token) internal view returns (bool) {
        return ((tokenFeatureList[_token] & BRIDGEABLE_TOKEN) == BRIDGEABLE_TOKEN);
    }

    function _needCall(address target, uint256 len) internal view returns (bool) {
        return (len > 0 && target.code.length > 0);
    }
}
