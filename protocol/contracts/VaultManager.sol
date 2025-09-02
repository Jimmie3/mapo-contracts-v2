// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./libs/Utils.sol";
import "./interfaces/IVaultToken.sol";
import "./interfaces/IRegistry.sol";

import {IVaultManager} from "./interfaces/IVaultManager.sol";

import { ChainType, TransferItem } from "./libs/Types.sol";
import { Errs } from "./libs/Errors.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {UintToUintMap, AddressToUintMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";

contract VaultManager is BaseImplementation, IVaultManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant MAX_MIGRATION_AMOUNT = 3;

    // for contract chain
    // migration don't include the migration token number, so how to update balance for new vault
    // if keep a unique balance, how to check should use the old or new vault
    struct ChainAllowance {
        bool migrationPending;      // set true after start a migration, reset after migration txOut on relay chain.

        // used by non-contract chain
        uint8 migrationIndex;

        uint256 tokenAllowances;
        uint256 tokenPendingOutAllowances;
    }

    struct Vault {
        EnumerableSet.UintSet chains;
        bytes pubkey;

        mapping(uint256 => ChainAllowance) chainAllowances;
    }

    // only one active vault and one retiring vault at a time
    bytes32 activeVaultKey;
    bytes32 retiringVaultKey;

    mapping(bytes32 => Vault) vaults;

    address public relay;

    IPeriphery public periphery;

    // for rebalancing calculation
    // token => totalWeight
    mapping(address => uint256) tokenTotalWeights;
    // token => chain => weight
    mapping(address => mapping(uint256 => uint256)) tokenChainWeights;
    // token => totalAllowance
    mapping(address => uint256) tokenTotalAllowance;

    // token => chain => targetBalance
    mapping(address => mapping(uint256 => uint256)) tokenTargetBalances;

    // token => chain => allowance
    mapping(address => mapping(uint256 => uint256)) tokenAllowances;
    mapping(address => mapping(uint256 => uint256)) tokenPendingOutAllowances;




    modifier onlyRelay() {
        if (msg.sender != address(relay)) revert no_access();
        _;
    }

    function rotate(bytes memory retiringVault, bytes memory activeVault) external override onlyRelay {
        activeVaultKey = keccak256(activeVault);
        retiringVaultKey = keccak256(retiringVault);
    }


    function checkMigration() external override onlyRelay returns (bool completed, uint256 toMigrateChain) {
        // check the retiring vault first
        if (retiringVaultKey == bytes32(0x00)) {
            return (true, 0);
        }

        Vault storage v = vaults[retiringVaultKey];
        uint256[] memory chains = v.chains.values();
        for (uint256 i = 0; i < chains.length(); i++) {
            uint256 chain = chains[i];
            if (v.chainAllowances[chain].migrationPending) {
                // migrating, continue to other chain migration
                continue;
            }

            return (false, chain);
        }

        if (v.chains.length() > 0) {
            return (false, 0);
        }
        // retiring vault migration completed
        // return and wait update tss vault status
        retiringVaultKey = bytes32(0x00);
        return (true, 0);
    }

    function migrate(uint256 _chain, uint256 fee) external onlyRelay returns (bool toMigrate, bytes memory fromVault, bytes memory toVault, uint256 amount) {
        if (periphery.getChainType() == ChainType.CONTRACT) {
            // token allowances managed by a global allowance
            // switch to active vault after migration when choosing vault
            vaults[retiringVaultKey].chainAllowances[_chain].migrationPending = true;

            vaults[activeVaultKey].chains.add(_chain);
            return (true, vaults[retiringVaultKey].pubkey, vaults[activeVaultKey].pubkey, 0);
        }

        ChainAllowance storage p = vaults[retiringVaultKey].chainAllowances[_chain];
        uint256 amount = p.tokenAllowances - p.tokenPendingOutAllowances;
        // todo: add min amount
        if (amount <= fee) {
            if (p.tokenPendingOutAllowances > 0) {
                return (false, fromVault, toVault, 0);
            }
            // no need migration
            vaults[retiringVaultKey].remove(_chain);
            delete vaults[retiringVaultKey].chainAllowances[_chain];

            return (false, fromVault, toVault, 0);
        }

        vaults[retiringVaultKey].chainAllowances[_chain].migrationPending = true;

        uint256 migrationAmount = amount / (MAX_MIGRATION_AMOUNT - p.migrationIndex);
        if (migrationAmount <= fee || (amount - migrationAmount) <= fee) {
            migrationAmount = amount;
        }
        p.migrationIndex++;

        p.tokenPendingOutAllowances += (migrationAmount + fee);

        return (true, vaults[retiringVaultKey].pubkey, vaults[activeVaultKey].pubkey, migrationAmount);
    }

    function chooseVault(uint256 chain, address token, uint256 amount, uint256 gas) external onlyRelay returns (bytes32 vault) {
        if (periphery.getChainType() == ChainType.CONTRACT) {
            if (vaults[activeVaultKey].chains.contains(chain)) {
                return activeVaultKey;
            } else {
                return retiringVaultKey;
            }
        }
        // non-contract chain
        // choose active vault first, if not match, choose retiring vault
        ChainAllowance storage p = vaults[activeVaultKey].chainAllowances[chain];
        uint256 allowance = p.tokenAllowances - p.tokenPendingOutAllowances;
        if (allowance >= amount + gas) {
            return activeVaultKey;
        }

        p = vaults[retiringVaultKey].chainAllowances[chain];
        allowance = p.tokenAllowances - p.tokenPendingOutAllowances;
        if (allowance >= amount + gas) {
            return retiringVaultKey;
        }

        return bytes32(0x00);
    }

    function migrationOut(TransferItem memory txItem, bytes memory toVault, uint256 estimatedGas, uint256 usedGas) external override onlyRelay {
        bytes32 vaultKey = keccak256(txItem.vault);
        bytes32 targetVaultKey = keccak256(toVault);
        if (vaultKey != retiringVaultKey || targetVaultKey != activeVaultKey) revert Errs.invalid_vault();

        if (periphery.getChainType() == ChainType.CONTRACT) {
            delete vaults[vaultKey].chainAllowances[txItem.chain];
            vaults[vaultKey].chains.remove(txItem.chain);
        } else {
            ChainAllowance storage p = vaults[vaultKey].chainAllowances[txItem.chain];
            p.migrationPending = false;

            p.tokenAllowances -= (txItem.amount + usedGas);
            p.tokenPendingOutAllowances -= (txItem.amount + estimatedGas);

            vaults[targetVaultKey].chains.add(txItem.chain);
            vaults[targetVaultKey].chainAllowances[txItem.chain].tokenAllowances += txItem.amount;

            tokenTotalAllowance[txItem.token] -= usedGas;
        }
    }

    function deposit(uint256 chain, bytes32 vaultKey, address token, uint256 amount) external onlyRelay {
        // todo: update target allowance

    }

    function withdraw(uint256 chain, bytes32 vaultKey, address token, uint256 amount) external onlyRelay {
        // todo: update target allowance

    }

    // tx in, add liquidity or swap in
    function transferIn(uint256 fromChain, bytes memory vault, address token, uint256 amount) external onlyRelay returns (bool) {
        bytes32 vaultKey = keccak256(vault);

        if (vaultKey != activeVaultKey && vaultKey != retiringVaultKey) {
            return false;
        }

        tokenTotalAllowance[token] += amount;
        tokenAllowances[token][fromChain] += amount;

        if (periphery.getChainType() == ChainType.CONTRACT) {
            // todo: add chain to active vault ?
            return true;
        }

        vaults[vaultKey].chains.add(fromChain);
        vaults[vaultKey].chainAllowances[fromChain].tokenAllowances += amount;

        return true;
    }

    // tx out, remove liquidity or swap out
    function transferOut(uint256 toChain, bytes memory vault, address token, uint256 amount, uint256 gasFee) external onlyRelay {
        bytes32 vaultKey = keccak256(vault);

        if (vaultKey != activeVaultKey && vaultKey != retiringVaultKey) {
            return;
        }

        if (periphery.getChainType() == ChainType.CONTRACT) {
            tokenPendingOutAllowances[token][toChain] += amount;

            return;
        }

        tokenPendingOutAllowances[token][toChain] += (amount + gasFee);

        vaults[vaultKey].chains.add(toChain);
        vaults[vaultKey].chainAllowances[toChain].tokenPendingOutAllowances += (amount + gasFee);
    }

    // bridge
    function transfer(ChainType _t, uint256 chain, bytes32 vaultKey, address token, uint256 amount) external onlyRelay {
        // todo: calculate balance fee

    }


}
