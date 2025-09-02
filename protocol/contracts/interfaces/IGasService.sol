// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGasService {
    function getNetworkFee(uint256 chain, bool withCall) external view returns (uint256 networkFee);
    function getNetworkFeeWithToken(uint256 chain, bool withCall, address token)
        external
        view
        returns (uint256 networkFee);

    function postNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionSize,
        uint256 transactionSizeWithCall,
        uint256 transactionRate
    ) external;

    function getNetworkFeeInfo(uint256 chain)
        external
        view
        returns (uint256 transactionRate, uint256 transactionSize, uint256 transactionSizeWithCall);
}
