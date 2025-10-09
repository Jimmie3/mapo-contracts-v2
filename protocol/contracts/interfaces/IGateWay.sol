// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGateway {
    function deposit(address token, uint256 amount, address to, address refund, uint256 deadline)
        external
        payable
        returns (bytes32 orderId);

    function bridgeOut(
        address token,
        uint256 amount,
        uint256 toChain,
        bytes memory to,
        address refundAddr,
        bytes memory payload,
        uint256 deadline
    ) external payable returns (bytes32 orderId);
}
