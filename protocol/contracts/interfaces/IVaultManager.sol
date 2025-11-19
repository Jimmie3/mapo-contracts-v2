// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TxItem, GasInfo} from "../libs/Types.sol";

interface IVaultManager {

    function getBridgeChains() external view returns(uint256[] memory);

    function getBridgeTokens() external view returns (address[] memory);

    function getVaultToken(address relayToken) external view returns(address);

    function getVaultTokenBalance(bytes calldata vault, uint256 chain, address token) external view returns(int256 balance, uint256 pendingOut);

    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
    external
    view
    returns (bool, uint256);

    function checkMigration() external view returns (bool completed, uint256 toMigrateChain);

    function checkVault(TxItem calldata txItem, bytes calldata vault) external view returns (bool);

    function getActiveVaultKey() external view returns (bytes32);

    function getActiveVault() external view returns (bytes memory);

    function getRetiringVault() external view returns (bytes memory);

    function rotate(bytes calldata retiringVault, bytes calldata activeVault) external;

    function addChain(uint256 chain) external;

    function removeChain(uint256 chain) external;


    /**
     * @notice Execute vault migration from retiring vault to active vault
     * @dev Returns migration details for the next chain to migrate. Contract chains update vault mapping only; non-contract chains physically migrate assets
     * @return completed True if all migrations are finished (no pending and no chains to migrate)
     * @return txItem Migration transaction details including chain, token, and amount. If chain == 0, no new migration but has pending transactions
     * @return gasInfo Gas information for the migration transaction
     * @return fromVault The retiring vault public key (source of migration)
     * @return toVault The active vault public key (destination of migration)
     */
    function migrate() external returns (bool completed, TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault);

    /**
     * @notice Process vault operations for a refund transaction
     * @dev Calculates refund amount after gas deduction, updates vault state for active/retiring vaults only
     * @param txItem The transaction to refund
     * @param vault The vault public key on refund destination chain
     * @param fromRetiredVault True if refunding from a retired vault (no vault state update), false for active/retiring vault (updates state)
     * @return refundAmount The amount to refund after gas deduction
     * @return gasInfo Gas information for the refund transaction
     */
    function refund(TxItem calldata txItem, bytes calldata vault, bool fromRetiredVault) external returns  (uint256 refundAmount, GasInfo memory gasInfo);

    /**
     * @notice Process vault operations for depositing assets to receive vault tokens
     * @dev Updates source vault balance and mints vault tokens to recipient
     * @param txItem The deposit transaction item (specifies source chain)
     * @param vault The source vault public key
     * @param to The recipient address for minted vault tokens
     */
    function deposit(TxItem calldata txItem, bytes calldata vault, address to) external;

    /**
     * @notice Process vault operations for redeeming vault tokens to withdraw assets
     * @dev Burns vault tokens, updates vault state for asset withdrawal from relay chain
     * @param vaultToken The vault token contract address
     * @param share The amount of vault tokens to redeem
     * @param owner The owner of the vault tokens
     * @param receiver The recipient of the underlying assets
     * @return amount The amount of underlying assets to be withdrawn
     */
    function redeem(address vaultToken, uint256 share, address owner, address receiver) external returns (uint256 amount);

    // /**
    //  * @notice Process vault operations for a bridge transfer
    //  * @dev Updates source vault, collects bridge fees and vault fees, selects target vault, and calculates cross-chain amount and gas
    //  * @param txItem The source transaction item
    //  * @param fromVault The source vault public key
    //  * @param toChain The destination chain ID
    //  * @param withCall True if destination includes swap data (used for gas estimation)
    //  * @return choose True if a suitable vault is available for the transfer
    //  * @return outAmount The amount to send to destination after fees and gas deduction
    //  * @return toVault The selected target vault public key on destination chain
    //  * @return gasInfo Gas information for the destination chain transaction
    //  */
    function bridgeOut(TxItem calldata txItem, bytes calldata fromVault, uint256 toChain, bool withCall) external returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo);


    function updateFromVault(TxItem calldata txItem, bytes calldata fromVault, uint256) external;

    /**
     * @notice Process vault operations for incoming transfer to relay chain
     * @dev Updates source vault and collects transfer-in fees and vault fees
     * @param txItem The incoming transaction item (specifies source chain)
     * @param fromVault The source vault public key
     * @param toChain The final destination chain ID (for auxiliary judgment, currently unused)
     * @return outAmount The amount after fees deduction
     */
    function transferIn(TxItem calldata txItem, bytes calldata fromVault, uint256 toChain) external returns (uint256 outAmount);

    /**
     * @notice Process vault operations for outgoing transfer from relay chain
     * @dev Collects transfer-out fees and vault fees, selects target vault, and calculates cross-chain amount and gas
     * @param txItem The transaction item to transfer out
     * @param fromChain The actual source chain ID (for auxiliary judgment, currently unused)
     * @param withCall True if destination includes swap data (used for gas estimation)
     * @return choose True if a suitable vault is available for the transfer
     * @return outAmount The amount to send after fees and gas deduction
     * @return toVault The selected target vault public key on destination chain
     * @return gasInfo Gas information for the destination chain transaction
     */
    function transferOut(TxItem calldata txItem, uint256 fromChain, bool withCall) external returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo);

    /**
     * @notice Update vault state after transfer is confirmed on destination chain
     * @dev Updates target vault balance, clears pending amounts based on actual gas usage
     * @param txItem The completed transaction item
     * @param vault The target vault public key on destination chain
     * @param usedGas The actual gas used on destination chain, converted to relay chain token amount
     * @param estimatedGas The previously estimated gas for destination chain execution
     * @return reimbursedGas The gas amount to reimburse to maintainer (for contract chains, return estimated gas)
     * @return amount The amount to burn on relay chain to match actual vault balance (for non-contract chains)
     */
    function transferComplete(TxItem calldata txItem, bytes calldata vault, uint128 usedGas, uint128 estimatedGas) external returns (uint256 reimbursedGas, uint256 amount);

    /**
     * @notice Update vault states after migration transaction is confirmed on chain
     * @dev Updates retiring vault (fromVault) and active vault (toVault) states, uses reserved fees to cover migration gas
     * @param txItem The completed migration transaction item
     * @param fromVault The retiring vault public key (source of migration)
     * @param toVault The active vault public key (destination of migration)
     * @param usedGas The actual gas used for the migration transaction
     * @param estimatedGas The estimated gas for the migration transaction
     * @return reimbursedGas The gas amount to reimburse to maintainer (for contract chains, return estimated gas)
     * @return amount The amount to burn on relay chain to match actual vault balance (for non-contract chains)
     */
    function migrationComplete(TxItem calldata txItem, bytes calldata fromVault, bytes calldata toVault, uint128 usedGas, uint128 estimatedGas) external returns (uint256 reimbursedGas, uint256 amount);
}
