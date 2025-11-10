// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TxItem, GasInfo} from "../libs/Types.sol";

interface IVaultManager {

    function getVaultTokenBalance(bytes memory vault, uint256 chain, address token) external view returns(int256 balance, uint256 pendingOut);

    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
    external
    view
    returns (bool, uint256);

    function checkMigration() external view returns (bool completed, uint256 toMigrateChain);

    function checkVault(TxItem calldata txItem, bytes calldata vault) external view returns (bool);

    function getActiveVault() external view returns (bytes memory);

    function getRetiringVault() external view returns (bytes memory);


    function rotate(bytes calldata retiringVault, bytes calldata activeVault) external;

    function addChain(uint256 chain) external;

    function removeChain(uint256 chain) external;


    function migrate() external returns (bool completed, TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault);

    function refund(TxItem calldata txItem, bytes calldata vault, bool fromRetiredVault) external returns  (uint256 refundAmount, GasInfo memory gasInfo);

    function deposit(TxItem calldata txItem, bytes calldata vault, address to) external;

    function redeem(address _vaultToken, uint256 _share, address _owner, address _receiver) external returns (uint256 amount);

    function bridge(TxItem calldata txItem, bytes calldata fromVault, uint256 toChain, bool withCall) external returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo);

    function transferIn(TxItem calldata txItem, bytes calldata fromVault, uint256 toChain) external returns (uint256 outAmount);

    function transferOut(TxItem memory txItem, uint256 fromChain, bool withCall) external returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo);

    function transferComplete(TxItem calldata txItem, bytes calldata vault, uint256 relayGasUsed, uint256 relayGasEstimated) external returns (uint256 gas, uint256 amount);

    function migrationComplete(TxItem calldata txItem, bytes calldata fromVault, bytes calldata toVault, uint256 estimatedGas, uint256 usedGas) external returns (uint256 gas, uint256 amount);
}
