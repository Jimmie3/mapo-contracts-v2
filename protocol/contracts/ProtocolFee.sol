// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

import {IProtocolFee} from "./interfaces/periphery/IProtocolFee.sol";

contract ProtocolFee is BaseImplementation, IProtocolFee {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    address constant NATIVE_TOKEN = address(0x00);
    uint256 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps
    uint256 constant MAX_TOTAL_RATE = 100_000;           // 10%

    error invalid_token_balance(address, uint256);

    struct FeeShare {
        uint64 share;
        address receiver;
    }

    uint256 public totalRate;

    uint256 public totalShare;
    mapping(FeeType => FeeShare) private feeShares;

    EnumerableSet.AddressSet private tokenList;

    // fee info from last share reset
    mapping(address token => uint256) public totalClaimed;
    mapping(address token => mapping(FeeType => uint256)) public claimed;

    // accumulated fee info from start
    mapping(address token => mapping(FeeType => uint256)) public accumulated;

    event UpdateProtocolFee(uint256 feeRate);

    event UpdateToken(address indexed token, bool add);

    event UpdateReceiver(FeeType feeType, address receiver);
    event UpdateShare(FeeType feeType, uint256 share, uint256 totalShare);

    event CollectProtocolFee(address indexed token, uint256 amount);
    event ClaimFee(FeeType feeType, address token, uint256 amount);


    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    receive() external payable {}

    function updateProtocolFee(uint256 feeRate) external restricted {
        require(feeRate < MAX_TOTAL_RATE);
        totalRate = feeRate;

        emit UpdateProtocolFee(feeRate);
    }

    function updateTokens(address[] memory tokens, bool added) external restricted {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (added) {
                tokenList.add(tokens[i]);
            } else {
                tokenList.remove(tokens[i]);
            }
            emit UpdateToken(tokens[i], added);
        }
    }

    function updateShares(FeeType[] memory types, uint64[] memory shares) external restricted {
        require (types.length == shares.length);
        require (types.length > 0);

        // release all token
        uint256 length = tokenList.length();
        for (uint256 i = 0; i < length; i++) {
            address token = tokenList.at(i);
            uint256 balance = _balance(token);
            if (balance > 0) revert invalid_token_balance(token, balance);

            totalClaimed[token] = 0;
            claimed[token][FeeType.DEV] = 0;
            claimed[token][FeeType.BUYBACK] = 0;
            claimed[token][FeeType.RESERVE] = 0;
            claimed[token][FeeType.STAKER] = 0;
        }

        length = types.length;
        for (uint256 i = 0; i < length; i++) {
            FeeShare storage feeShare = feeShares[types[i]];
            totalShare = totalShare - feeShare.share + shares[i];
            feeShare.share = shares[i];

            emit UpdateShare(types[i], shares[i], totalShare);
        }
    }

    function updateReceivers(FeeType[] memory types, address[] memory receivers) external restricted {
        require (types.length == receivers.length);
        require (types.length > 0);

        uint256 length = types.length;
        for (uint256 i = 0; i < length; i++) {
            feeShares[types[i]].receiver = receivers[i];
            emit UpdateReceiver(types[i], receivers[i]);
        }
    }

    function getCumulativeFee(FeeType feeType, address token) external view override returns (uint256) {
        return accumulated[token][feeType];
    }

    function getClaimable(FeeType feeType, address token) external view override returns (uint256) {
        return _getClaimable(feeType, token);
    }

    function getProtocolFee(address, uint256 amount) external view override returns (uint256) {
        return (amount * totalRate / MAX_RATE_UNIT);
    }

    function claim(FeeType feeType, address[] memory tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 claimable = _getClaimable(feeType, token);
            if (claimable > 0) {
                tokenList.add(token);

                totalClaimed[token] += claimable;
                claimed[token][feeType] += claimable;

                accumulated[token][feeType] += claimable;

                _release(token, feeShares[feeType].receiver, claimable);

                emit ClaimFee(feeType, token, claimable);
            }
        }
    }

    function _getClaimable(FeeType feeType, address token) internal view returns (uint256) {
        uint256 totalCollected = _balance(token) + totalClaimed[token];
        uint256 totalAvailable = totalCollected * feeShares[feeType].share / totalShare;

        return (totalAvailable - claimed[token][feeType]);
    }

    function _balance(address token) internal view returns (uint256) {
        if (token == NATIVE_TOKEN) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function _release(address token, address account, uint256 amount) internal {
        if (token == NATIVE_TOKEN) {
            Address.sendValue(payable(account), amount);
        } else {
            SafeERC20.safeTransfer(IERC20(token), account, amount);
        }
    }

}
