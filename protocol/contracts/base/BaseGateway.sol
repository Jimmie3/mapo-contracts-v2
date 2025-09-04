// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IReceiver} from "../interfaces/IReceiver.sol";
import {TxType} from "../libs/Types.sol";
import {IMintableToken} from "../interfaces/IMintableToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

abstract contract BaseGateway is BaseImplementation, ReentrancyGuardUpgradeable {
    address internal constant ZERO_ADDRESS = address(0);
    uint256 internal constant MIN_GAS_FOR_LOG = 10_000;

    uint256 constant MINTABLE_TOKEN = 0x01;
    uint256 constant BRIDGABLE_TOKEN = 0x02;

    uint256 public immutable selfChainId = block.chainid;

    uint256 private nonce;
    address public wToken;

    // token => feature
    mapping(address => uint256) public tokenFeatureList;

    event SetWToken(address _wToken);

    event TransferIn(bytes32 orderId, address token, uint256 amount, address to, bool result);

    event BridgeOut( // fromChain (8 bytes) | toChain (8 bytes) | reserved (16 bytes)
        bytes32 indexed orderId,
        uint256 indexed chainAndGasLimit,
        TxType txOutType,
        bytes vault,
        address token,
        uint256 amount,
        address from,
        bytes to,
        bytes data
    );

    event BridgeIn( // fromChain (8 bytes) | toChain (8 bytes) | reserved (8 bytes) | gasUsed (8 bytes)
    // maintainer
        bytes32 indexed orderId,
        uint256 indexed chainAndGasLimit,
        TxType txInType,
        bytes vault,
        uint256 sequence,
        address sender,
        address to,
        bytes data
    );

    error transfer_in_failed();
    error transfer_out_failed();
    error order_executed();
    error zero_address();
    error invalid_signature();

    function setWtoken(address _wToken) external restricted {
        require(_wToken != ZERO_ADDRESS);
        wToken = _wToken;
        emit SetWToken(_wToken);
    }

    function deposit(address token, uint256 amount, address to)
    external
    payable virtual
    whenNotPaused
    nonReentrant
    returns (bytes32 orderId)
    {
    }

    function bridgeOut(address token, uint256 amount, uint256 toChain, bytes memory to, bytes memory payload)
    external
    payable virtual
    whenNotPaused
    nonReentrant
    returns (bytes32 orderId)
    {
    }

    function _transferOut(bytes32 orderId, bytes calldata to, bytes calldata data) internal {
        uint256 amount;
        bytes memory tokenBytes;
        bytes memory payload;
        (amount, tokenBytes, payload) = abi.decode(data, (uint256, bytes, bytes));
        address token = _fromBytes(tokenBytes);
        address to_addr = _fromBytes(to);
        require(to_addr != ZERO_ADDRESS);
        require(amount != 0);
        bool result = _safeTransferOut(orderId, token, to_addr, amount, payload);
        emit TransferIn(orderId, token, amount, to_addr, result);
    }


    function _safeTransferOut(bytes32 orderId, address token, address to, uint256 value, bytes memory payload)
    internal
    returns (bool result)
    {
        address _wToken = wToken;
        bool needCall = _needCall(to, payload.length);
        if (token == _wToken && !needCall) {
            bool success;
            bytes memory data;
            // unwrap wToken
            (success, data) = _wToken.call(abi.encodeWithSelector(0x2e1a7d4d, value));
            result = (success && (data.length == 0 || abi.decode(data, (bool))));
            if (result) {
                // todo: native token might transfer failed, need a fallback option
                // transfer native token to the recipient
                (success, data) = to.call{value: value}("");
            } else {
                // if unwrap failed, fallback to transfer wToken
                (success, data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
            }
            result = (success && (data.length == 0 || abi.decode(data, (bool))));
        } else {
            // todo: token might transfer failed, such as transfer usdt to usdt contract address, need fallback or retry option
            // bytes4(keccak256(bytes('transfer(address,uint256)')));  transfer
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
            result = (success && (data.length == 0 || abi.decode(data, (bool))));
            if (result && needCall) {
                uint256 gasForCall = gasleft() - MIN_GAS_FOR_LOG;
                try IReceiver(to).onReceived{gas: gasForCall}(orderId, token, value, payload) {} catch {}
            }
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
        }
    }

    function _needCall(address target, uint256 len) internal view returns (bool) {
        return (len > 0 && target.code.length > 0);
    }

    function _getOrderId(address user, address token, uint256 amount) internal returns (bytes32 orderId) {
        return keccak256(abi.encodePacked(_getChainId(), user, token, amount, ++nonce));
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

    function _getChainId() internal view returns (uint256) {
        return selfChainId;
    }

    function _fromBytes(bytes memory b) internal pure returns (address addr) {
        assembly {
            addr := mload(add(b, 20))
        }
    }
}
