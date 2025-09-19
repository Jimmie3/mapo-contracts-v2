// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./libs/Utils.sol";
import "./interfaces/IVaultToken.sol";
import "./interfaces/IRegistry.sol";

import {IVaultManager} from "./interfaces/IVaultManager.sol";

import {ChainType, TxItem} from "./libs/Types.sol";
import {Errs} from "./libs/Errors.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";

contract VaultManager is BaseImplementation, IVaultManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    uint256 private constant MAX_MIGRATION_AMOUNT = 3;
    bytes32 private constant NON_VAULT_KEY = bytes32(0x00);


    struct ChainAllowance {
        bool migrationPending; // set true after start a migration, reset after migration txOut on relay chain.
        // used by non-contract chain
        uint8 migrationIndex;
        uint128 tokenAllowances;
        uint128 tokenPendingOutAllowances;
    }

    struct Vault {
        EnumerableSet.UintSet chains;
        bytes pubkey;
        mapping(uint256 => ChainAllowance) chainAllowances;
    }

    // only one active vault and one retiring vault at a time
    // after migration, only one active vault, no retiring vault
    bytes32 public activeVaultKey;
    bytes32 public retiringVaultKey;

    mapping(bytes32 => Vault) private vaultList;

    // token => vaultToken
    EnumerableMap.AddressToAddressMap tokenList;

    EnumerableSet.UintSet chainList;        // all support chains

    address public relay;

    IPeriphery public periphery;

    struct ChainTokenState {
        bool mintable;              // token is mintable at this chain
                                    // if token is mintable, all other data will be 0
        uint64 weight;              // chain weight for target balance
        uint128 balance;            // token balance
        uint128 pendingOut;         // token pendingOut balance
        uint128 reserved;           // reserved for transfer out
        uint128 target;             // target balance
    }

    struct TotalTokenState {
        uint128 totalBalance;
        uint128 totalPendingOut;
        uint64 totalWeight;
    }

    mapping(address => TotalTokenState) public totalStates;
    mapping(address => mapping(uint256 => ChainTokenState)) public chainStates;

    event SetRelay(address _relay);
    event SetPeriphery(address _periphery);

    modifier onlyRelay() {
        if (msg.sender != address(relay)) revert Errs.no_access();
        _;
    }

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setRelay(address _relay) external restricted {
        require(_relay != address(0));
        relay = _relay;
        emit SetRelay(_relay);
    }

    function setPeriphery(address _periphery) external restricted {
        require(_periphery != address(0));
        periphery = IPeriphery(_periphery);
        emit SetPeriphery(_periphery);
    }

    function updateTokenWeights(address token, uint256[] memory chains, uint256[] memory weights) external restricted {
        uint256 len = chains.length;
        require(len == weights.length);
        uint256 i;
        uint256 chain;

        TotalTokenState storage totalState = totalStates[token];
        for (i = 0; i < len; i++) {
            chain = chains[i];

            ChainTokenState storage chainState = chainStates[token][chain];
            totalState.totalWeight = totalState.totalWeight - chainState.weight + uint64(weights[i]);
            chainState.weight = uint64(weights[i]);
        }
        // update target balance
        _updateTokenTargetBalance(token);
    }

    function _updateTokenTargetBalance(address token) internal {
        TotalTokenState memory totalState = totalStates[token];
        uint256 len = chainList.length();
        for (uint i = 0; i < len; i++) {
            uint256 chain = chainList.at(i);
            ChainTokenState storage chainState = chainStates[token][chain];
            if (chainState.weight == 0 && chainState.target == 0) {
                continue;
            }
            chainState.target = totalState.totalBalance * chainState.weight / totalState.totalWeight;
        }
    }

    function rotate(bytes memory retiringVault, bytes memory activeVault) external override onlyRelay {
        activeVaultKey = keccak256(activeVault);
        retiringVaultKey = keccak256(retiringVault);
        vaultList[activeVaultKey].pubkey = activeVault;
    }

    function addChain(uint256 chain) external override onlyRelay {
        chainList.add(chain);
        // vaultList[activeVaultKey].chains.add(chain);

        // todo: emit event
    }

    function removeChain(uint256 chain) external override onlyRelay {
        // check all balance
        address[] memory tokens = tokenList.keys();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (totalStates[tokens[i]].totalBalance > 0) revert Errs.token_allowance_not_zero();
        }
        chainList.remove(chain);
        // vaultList[activeVaultKey].chains.remove(chain);
        // todo: emit event
    }

    function checkMigration() external override onlyRelay returns (bool completed, uint256 toMigrateChain) {
        // check the retiring vault first
        if (retiringVaultKey == NON_VAULT_KEY) {
            // no retiring vault, no need migration
            return (true, 0);
        }

        Vault storage v = vaultList[retiringVaultKey];
        uint256[] memory chains = v.chains.values();
        for (uint256 i = 0; i < chains.length; i++) {
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
        retiringVaultKey = NON_VAULT_KEY;
        return (true, 0);
    }

    function migrate(uint256 _chain, uint256 gasFee)
        external
        onlyRelay
        returns (bool toMigrate, bytes memory fromVault, bytes memory toVault, uint256 migrationAmount)
    {
        if (periphery.getChainType(_chain) == ChainType.CONTRACT) {
            // token allowances managed by a global allowance
            // switch to active vault after migration when choosing vault
            vaultList[retiringVaultKey].chainAllowances[_chain].migrationPending = true;

            vaultList[activeVaultKey].chains.add(_chain);
            return (true, vaultList[retiringVaultKey].pubkey, vaultList[activeVaultKey].pubkey, 0);
        }

        ChainAllowance storage p = vaultList[retiringVaultKey].chainAllowances[_chain];
        uint256 amount = p.tokenAllowances - p.tokenPendingOutAllowances;

        // todo: add min amount
        if (amount <= gasFee) {
            // no need migration

            if (p.tokenPendingOutAllowances > 0) {
                return (false, fromVault, toVault, 0);
            }

            vaultList[retiringVaultKey].chains.remove(_chain);
            delete vaultList[retiringVaultKey].chainAllowances[_chain];

            return (false, fromVault, toVault, 0);
        }

        vaultList[retiringVaultKey].chainAllowances[_chain].migrationPending = true;

        migrationAmount = amount / (MAX_MIGRATION_AMOUNT - p.migrationIndex);
        if (migrationAmount <= gasFee || (amount - migrationAmount) <= gasFee) {
            migrationAmount = amount;
        }
        p.migrationIndex++;

        p.tokenPendingOutAllowances += uint128(migrationAmount + gasFee);

        // todo: update total balance
        // ChainBalance storage chainBalance = tokenChainBalances[txItem.token][_chain];
        // chainBalance.pendingOut += gasFee;

        return (true, vaultList[retiringVaultKey].pubkey, vaultList[activeVaultKey].pubkey, migrationAmount);
    }

    function chooseVault(uint256 chain, address token, uint256 amount, uint256 gas)
        external
        view
        returns (bytes memory vault)
    {
        uint256 allowance;
        if (periphery.getChainType(chain) == ChainType.CONTRACT) {
            ChainTokenState storage chainBalance = chainStates[token][chain];
            allowance = chainBalance.balance - chainBalance.pendingOut;
            if (allowance < amount) return bytes("");
            if (vaultList[activeVaultKey].chains.contains(chain)) {
                return vaultList[activeVaultKey].pubkey;
            } else {
                return vaultList[retiringVaultKey].pubkey;
            }
        }
        // non-contract chain
        // choose active vault first, if not match, choose retiring vault
        ChainAllowance storage p = vaultList[activeVaultKey].chainAllowances[chain];
        allowance = p.tokenAllowances - p.tokenPendingOutAllowances;
        if (allowance >= amount + gas) {
            return vaultList[activeVaultKey].pubkey;
        }

        p = vaultList[retiringVaultKey].chainAllowances[chain];
        allowance = p.tokenAllowances - p.tokenPendingOutAllowances;
        if (allowance >= amount + gas) {
            return vaultList[retiringVaultKey].pubkey;
        }

        return bytes("");
    }

    function migrationOut(TxItem memory txItem, bytes memory fromVault, bytes memory toVault, uint256 estimatedGas, uint256 usedGas)
        external
        override
        onlyRelay
    {
        bytes32 vaultKey = keccak256(fromVault);
        bytes32 targetVaultKey = keccak256(toVault);
        if (vaultKey != retiringVaultKey || targetVaultKey != activeVaultKey) revert Errs.invalid_vault();

        if (periphery.getChainType(txItem.chain) == ChainType.CONTRACT) {
            delete vaultList[vaultKey].chainAllowances[txItem.chain];
            vaultList[vaultKey].chains.remove(txItem.chain);
        } else {
            ChainAllowance storage p = vaultList[vaultKey].chainAllowances[txItem.chain];
            p.migrationPending = false;

            p.tokenAllowances -= uint128(txItem.amount + usedGas);
            p.tokenPendingOutAllowances -= uint128(txItem.amount + estimatedGas);

            vaultList[targetVaultKey].chains.add(txItem.chain);
            vaultList[targetVaultKey].chainAllowances[txItem.chain].tokenAllowances += uint128(txItem.amount);

            totalStates[txItem.token].totalBalance -= uint128(usedGas);
            ChainTokenState storage chainBalance = chainStates[txItem.token][txItem.chain];
            chainBalance.balance -= uint128(usedGas);
            chainBalance.pendingOut -= uint128(estimatedGas);

            // todo: update target ?
        }
    }

    // tx in, add liquidity or swap in
    function transferIn(uint256 fromChain, bytes memory vault, address token, uint256 amount)
        external
        onlyRelay
        returns (bool)
    {
        bytes32 vaultKey = keccak256(vault);

        if (vaultKey != activeVaultKey && vaultKey != retiringVaultKey) {
            return false;
        }

        totalStates[token].totalBalance += uint128(amount);

        ChainTokenState storage chainBalance = chainStates[token][fromChain];
        chainBalance.balance += uint128(amount);

        _updateTokenTargetBalance(token);

        vaultList[vaultKey].chains.add(fromChain);

        if (periphery.getChainType(fromChain) == ChainType.CONTRACT) {
            return true;
        }

        // vaultList[vaultKey].chains.add(fromChain);
        vaultList[vaultKey].chainAllowances[fromChain].tokenAllowances += uint128(amount);

        return true;
    }

    // tx out, remove liquidity or swap out
    function transferOut(
        uint256 chain,
        bytes memory vault,
        address token,
        uint256 amount,
        uint256 relayGasUsed,
        uint256 relayGasEstimated
    ) external override onlyRelay {
        bytes32 vaultKey = keccak256(vault);

        if (vaultKey != retiringVaultKey || vaultKey != activeVaultKey) revert Errs.invalid_vault();

        TotalTokenState storage totalState = totalStates[token];
        ChainTokenState storage chainState = chainStates[token][chain];
        if (periphery.getChainType(chain) != ChainType.CONTRACT) {

            totalState.totalBalance -= uint128(amount + relayGasUsed);
            totalState.totalPendingOut -= uint128(amount + relayGasEstimated);

            chainState.balance -= uint128(amount + relayGasUsed);
            chainState.pendingOut -= uint128(amount + relayGasEstimated);

            vaultList[vaultKey].chainAllowances[chain].tokenAllowances -= uint128(amount + relayGasUsed);
            vaultList[vaultKey].chainAllowances[chain].tokenPendingOutAllowances -= uint128(amount + relayGasEstimated);
        } else {
            totalState.totalBalance -= uint128(amount);
            totalState.totalPendingOut -= uint128(amount);

            chainState.balance -= uint128(amount);
            chainState.pendingOut -= uint128(amount);
        }

        _updateTokenTargetBalance(token);
    }

    // bridge
    function doTransfer(uint256 toChain, bytes memory vault, address token, uint256 amount, uint256 estimatedGas)
        external
        override
        onlyRelay
    {
        // todo: calculate balance fee

        bytes32 vaultKey = keccak256(vault);

        if (vaultKey != activeVaultKey && vaultKey != retiringVaultKey) {
            return;
        }

        TotalTokenState storage totalState = totalStates[token];
        ChainTokenState storage chainState = chainStates[token][toChain];

        if (periphery.getChainType(toChain) == ChainType.CONTRACT) {

            totalState.totalPendingOut += uint128(amount);

            chainState.pendingOut += uint128(amount);

            return;
        }

        totalState.totalPendingOut += uint128(amount + estimatedGas);
        chainState.pendingOut += uint128(amount + estimatedGas);

        vaultList[vaultKey].chains.add(toChain);
        vaultList[vaultKey].chainAllowances[toChain].tokenPendingOutAllowances += uint128(amount + estimatedGas);
    }

    function checkVault(uint256 fromChain, bytes calldata vault) external view returns (bool) {
        if (periphery.getChainType(fromChain) == ChainType.CONTRACT) {
            // not check vault if source chain is a contract chain, checked by source gateway contract
            return true;
        }
        bytes32 vaultKey = keccak256(vault);
        return (vaultKey == retiringVaultKey || vaultKey == activeVaultKey);
    }

    function getActiveVault() external view override returns (bytes memory) {
        return vaultList[activeVaultKey].pubkey;
    }

    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
        external
        view
        override
        returns (uint256, bool)
    {}
}
