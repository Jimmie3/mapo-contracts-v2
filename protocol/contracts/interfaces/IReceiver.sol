// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReceiver {
    function onReceived(bytes32 _orderId, address _token, uint256 _amount, bytes calldata _payload) external;
}
