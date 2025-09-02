// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainType } from "./libs/Types.sol";

import { TransferItem, ChainType } from "./libs/Types.sol";

interface IVaultManager {
    function getVaultToken(address _token) external view returns (address);

    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
        external
        view
        returns (uint256, bool);

    function updateVault(uint256 fromChain, uint256 toChain, address token, uint256 amount) external;

    function getVaultBalanceByToken(uint256 chain, bytes memory token) external view returns (uint256 vaultBalance);

    function rotate(bytes memory retiringVault, bytes memory activeVault) external;

    function checkMigration() external returns (bool completed, uint256 toMigrateChain);

    function migrate(uint256 _chain, uint256 fee) external returns (bool toMigrate, bytes memory fromVault, bytes memory toVault, uint256 amount);

    function migrationOut(TransferItem memory txItem, bytes memory toVault, uint256 estimatedGas, uint256 usedGas) external;

    function chooseVault(uint256 chain, address token, uint256 amount, uint256 gas) external returns (bool result, bytes memory vault);

    function transferIn(uint256 fromChain, bytes memory vault, address token, uint256 amount) external returns (bool);

    function transferOut(uint256 toChain, bytes memory vault, address token, uint256 amount, uint256 gasFee) external;

}
