// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainType, TxItem, GasInfo} from "../libs/Types.sol";

interface IVaultManager {
    // function getVaultToken(address _token) external view returns (address);
    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
    external
    view
    returns (bool, uint256);

    function checkMigration() external view returns (bool completed, uint256 toMigrateChain);

    function checkVault(ChainType chainType, uint256 fromChain, bytes calldata vault) external view returns (bool);

    function getActiveVault() external view returns (bytes memory);

    function getRetiringVault() external view returns (bytes memory);

    function rotate(bytes memory retiringVault, bytes memory activeVault) external;

    function addChain(uint256 chain) external;

    function removeChain(uint256 chain) external;


    function migrate() external returns (bool completed, TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault);

    function refund(TxItem memory txItem, bytes memory vault, bool fromRetiredVault) external returns  (uint256 refundAmount, GasInfo memory gasInfo);

    function deposit(TxItem memory txItem, bytes memory vault) external;

    function bridge(TxItem memory txItem, bytes memory fromVault, uint256 toChain, bool withCall) external returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo);

    function transferIn(TxItem memory txItem, bytes memory fromVault, uint256 toChain) external returns (uint256 outAmount);

    function transferOut(TxItem memory txItem, uint256 fromChain, bool withCall) external returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo);

    function transferComplete(TxItem memory txItem, bytes memory vault, uint256 relayGasUsed, uint256 relayGasEstimated) external;

    function migrationComplete(TxItem memory txItem, bytes memory fromVault, bytes memory toVault, uint256 estimatedGas, uint256 usedGas) external;
}
