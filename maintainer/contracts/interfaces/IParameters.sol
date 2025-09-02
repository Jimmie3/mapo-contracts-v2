// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IParameters {
    function getByHash(bytes32 hash) external view returns(uint256 value);
}