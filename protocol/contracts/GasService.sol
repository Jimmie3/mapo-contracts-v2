// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ISwap} from "./interfaces/ISwap.sol";
import {IGasService} from "./interfaces/IGasService.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";
import {IHiveSwapV3Quoter} from "./interfaces/IHiveSwapV3Quoter.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

import {Errs} from "./libs/Errors.sol";

contract GasService is BaseImplementation, IGasService {
    struct NetworkFee {
        uint64 height;
        uint128 transactionRate;
        uint128 transactionSize;
        uint128 transactionSizeWithCall;
    }

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

    function postNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionSize,
        uint256 transactionSizeWithCall,
        uint256 transactionRate
    ) external override {
        _checkAccess(0);

        NetworkFee storage fee = chainNetworkFee[chain];
        fee.height = uint64(height);
        fee.transactionRate = uint128(transactionRate);
        fee.transactionSize = uint128(transactionSize);
        fee.transactionSizeWithCall = uint128(transactionSizeWithCall);
        emit PostNetworkFee(chain, height, transactionSize, transactionSizeWithCall, transactionRate);
    }

    function getNetworkFee(uint256 chain, bool withCall) external view override returns (uint256 networkFee) {
        (uint256 transactionRate, uint256 transactionSize, uint256 transactionSizeWithCall) = _getNetworkFeeInfo(chain);

        if (withCall) {
            transactionSize = transactionSizeWithCall;
        }

        networkFee = transactionSize * transactionRate;
    }


    function getNetworkFeeInfo(uint256 chain, bool withCall)
        external
        view
        override
        returns (uint256 networkFee, uint256 transactionRate, uint256 transactionSize)
    {
        uint256 transactionSizeWithCall;

        (transactionRate, transactionSize, transactionSizeWithCall) = _getNetworkFeeInfo(chain);

        if (withCall) {
            transactionSize = transactionSizeWithCall;
        }

        networkFee = transactionSize * transactionRate;
    }

    function getNetworkFeeInfo(uint256 chain)
    external
    view
    override
    returns (uint256 transactionRate, uint256 transactionSize, uint256 transactionSizeWithCall)
    {
        return _getNetworkFeeInfo(chain);
    }


    function _getNetworkFeeInfo(uint256 chain)
    internal
    view
    returns (uint256 transactionRate, uint256 transactionSize, uint256 transactionSizeWithCall)
    {
        NetworkFee memory fee = chainNetworkFee[chain];
        transactionRate = (fee.transactionRate * 3) / 2; // 1.5x rate
        transactionSize = fee.transactionSize;
        transactionSizeWithCall = fee.transactionSizeWithCall;
    }

    function _checkAccess(uint256 t) internal view {
        if (msg.sender != periphery.getAddress(t)) revert Errs.no_access();
    }
}
