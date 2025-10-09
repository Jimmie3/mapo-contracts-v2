// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainType, TxItem, GasInfo} from "../libs/Types.sol";

interface IVaultManager {

    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
        external
        view
        returns (uint256, bool);

    function rotate(bytes memory retiringVault, bytes memory activeVault) external;

    function addChain(uint256 chain) external;

    function removeChain(uint256 chain) external;

    function checkMigration() external returns (bool completed, uint256 toMigrateChain);

    function chooseVault(TxItem memory txItem, bool withCall)
    external
    view
    returns (bool chooseVault, uint256 outAmount, bytes memory vault, GasInfo memory gasInfo);

    function checkVault(ChainType chainType, uint256 fromChain, bytes calldata vault) external view returns (bool);

    function getActiveVault() external view returns (bytes memory);

    function getRetiringVault() external view returns (bytes memory);

    function getVaultTokenBalance(bytes memory vault, uint256 chain, address token) external view returns(uint256 balance, uint256 pendingOut);

    function migrate() external returns (bool completed, TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault);

    function chooseAndTransfer(TxItem memory txItem, bool withCall)
    external
    returns (bool choose, uint256 outAmount, bytes memory vault, GasInfo memory gasInfo);

    function refund(TxItem memory txItem, bytes memory vault) external returns  (uint256 refundAmount, GasInfo memory gasInfo);

    function deposit(TxItem memory txItem, bytes memory vault) external;

    function transferIn(uint256 fromChain, bytes memory vault, address token, uint256 amount) external returns (bool);

    function transferOut(
        uint256 chain,
        bytes memory vault,
        address token,
        uint256 amount,
        uint256 relayGasUsed,
        uint256 relayGasEstimated
    ) external;

    function migrationOut(TxItem memory txItem, bytes memory fromVault, bytes memory toVault, uint256 estimatedGas, uint256 usedGas) external;


}
