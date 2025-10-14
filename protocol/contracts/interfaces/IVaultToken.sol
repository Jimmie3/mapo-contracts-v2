// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVaultToken is IERC4626 {
    function collectFee(uint256 assets) external;
}
