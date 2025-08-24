// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//pragma experimental ABIEncoderV2;

interface IValidators {
    function isValidator(address) external view returns (bool);

    function getTopValidators(uint256 n) external view returns (address[] memory);
}
