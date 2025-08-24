// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IElection {
    function electValidatorSigners() external view returns (address[] memory);

    function electNValidatorSigners(uint256, uint256) external view returns (address[] memory);
    function getElectableValidators() external view returns (uint256, uint256);

    function getValidatorEligibility(address) external view returns (bool);

    function getTopValidators(uint256) external view returns (address[] memory);

    function getEligibleValidators() external view returns (address[] memory);

    function getCurrentValidatorSigners() external view returns (address[] memory);
}
