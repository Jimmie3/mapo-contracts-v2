// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {

    function getAddress(bytes32 salt) external view returns (address);
    function deploy(bytes32 salt, bytes memory creationCode, uint256 value) external;

}
