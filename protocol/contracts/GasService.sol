// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ISwap} from "./interfaces/ISwap.sol";
import {IGasService} from "./interfaces/IGasService.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IHiveSwapV3Quoter} from "./interfaces/IHiveSwapV3Quoter.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

import {Errs} from "./libs/Errors.sol";

contract GasService is BaseImplementation, IGasService {
    struct NetworkFee {
        uint256 height;
        uint256 transactionRate;
        uint256 transactionSize;
        uint256 transactionSizeWithCall;
    }

    ISwap public swap;
    IPeriphery public periphery;
    mapping(uint256 => NetworkFee) public chainNetworkFee;

    event SetSwap(address _swap);
    event SetPeriphery(address _periphery);
    event PostNetworkFee(
        uint256 chain, uint256 height, uint256 transactionSize, uint256 transactionSizeWithCall, uint256 transactionRate
    );

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setPeriphery(address _periphery) external restricted {
        require(_periphery != address(0));
        periphery = IPeriphery(_periphery);
        emit SetPeriphery(_periphery);
    }

    function setSwap(address _swap) external restricted {
        require(_swap != address(0));
        swap = ISwap(_swap);
        emit SetSwap(_swap);
    }

    function postNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionSize,
        uint256 transactionSizeWithCall,
        uint256 transactionRate
    ) external override {
        _checkAccess(4);

        NetworkFee storage fee = chainNetworkFee[chain];
        fee.height = height;
        fee.transactionRate = transactionRate;
        fee.transactionSize = transactionSize;
        fee.transactionSizeWithCall = transactionSizeWithCall;
        emit PostNetworkFee(chain, height, transactionSize, transactionSizeWithCall, transactionRate);
    }

    function getNetworkFee(uint256 chain, bool withCall) external view override returns (uint256 networkFee) {
        return _getNetworkFee(chain, withCall);
    }

    function getNetworkFeeWithToken(uint256 chain, bool withCall, address token)
        external
        view
        override
        returns (uint256 networkFee)
    {
        uint256 fee = _getNetworkFee(chain, withCall);
        IRegistry r = _getTokenRegistry();
        address gasToken = r.getChainGasToken(chain);
        uint256 relayChainFeeAmount = r.getRelayChainAmount(r.getToChainToken(gasToken, chain), chain, fee);
        networkFee = swap.getAmountOut(gasToken, token, relayChainFeeAmount);
    }

    function _getNetworkFee(uint256 chain, bool withCall) internal view returns (uint256 networkFee) {
        NetworkFee storage fee = chainNetworkFee[chain];
        require(fee.transactionRate > 0);
        uint256 rate = (fee.transactionRate * 3) / 2;
        uint256 limit;
        if (withCall) {
            limit = fee.transactionSizeWithCall;
        } else {
            limit = fee.transactionSize;
        }
        return rate * limit;
    }

    function getNetworkFeeInfo(uint256 chain)
        external
        view
        override
        returns (uint256 transactionRate, uint256 transactionSize, uint256 transactionSizeWithCall)
    {
        NetworkFee storage fee = chainNetworkFee[chain];
        transactionRate = (fee.transactionRate * 3) / 2; // 1.5x rate
        transactionSize = fee.transactionSize;
        transactionSizeWithCall = fee.transactionSizeWithCall;
    }

    function _getTokenRegistry() internal view returns (IRegistry tokenRegistry) {
        tokenRegistry = IRegistry(periphery.getAddress(3));
    }

    function _checkAccess(uint256 t) internal view {
        if (msg.sender != periphery.getAddress(t)) revert Errs.no_access();
    }
}
