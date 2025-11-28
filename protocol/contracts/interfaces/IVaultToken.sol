// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVaultToken is IERC4626 {

    function vaultManager() external view returns (address);
    function totalSupply() external view returns (uint256);

    function increaseVault(uint256 assets) external;
    function decreaseVault(uint256 assets) external;
}
