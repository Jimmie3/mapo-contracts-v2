// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./libs/Utils.sol";
import "./interfaces/IVaultToken.sol";
import "./interfaces/IRegistry.sol";

import {IVaultManager} from "./interfaces/IVaultManager.sol";

import {ChainType, TxItem, GasInfo, FeeInfo} from "./libs/Types.sol";
import {Errs} from "./libs/Errors.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";

/**
 * @title VaultManager
 * @dev Core vault management contract for cross-chain asset transfers
 *
 * ## Overview
 * VaultManager is responsible for managing vault operations across multiple chains,
 * handling vault rotations, migrations, and tracking token balances and allowances.
 * It maintains both active and retiring vaults to ensure smooth transitions during
 * vault updates.
 *
 * ## Vault Management Principles
 *
 * ### 1. Vault Selection Strategy
 * - **Contract Chains**: Always use the active vault for outgoing transfers by default.
 *   The contract maintains chain-specific vault assignments during migrations.
 * - **Non-Contract Chains**: Select vault based on available token allowances,
 *   prioritizing active vault first, then falling back to retiring vault if needed.
 *
 * ### 2. Refund Mechanism
 * - **Retired Vault**: If a vault is retired (not active or retiring), execute refund
 *   to return assets to the sender.
 * - **Insufficient Funds After Swap**: If after relay chain fee deduction and token swap,
 *   the amount is less than expected minimum, trigger refund. Affiliate fees and
 *   security fees are still deducted before refund.
 *
 * ### 3. Fee Structure for Transfers
 * - **Target Chain Transfer**: Deduct base fee (gas fee) when transferring to target chain.
 *   If balance is below the base fee, initiate refund process.
 * - **Balance Fee**: Additional fees may apply based on vault balance management needs,
 *   can be positive (incentive) or negative (fee) depending on rebalancing requirements.
 *
 * ### 4. Refund Fee Management
 * - **Gas Fee Deduction**: During refund, source chain gas fees are deducted.
 * - **Minimum Amount Check**: If the refund amount after gas fee is below minimum
 *   threshold, the refund is cancelled to avoid dust transactions.
 *
 * ### 5. Migration Process
 * - **Contract Chains**: Only update vault key mappings, no actual asset migration.
 *   The chain is immediately assigned to the new active vault.
 * - **Non-Contract Chains**: Physically migrate assets from retiring vault address
 *   to new active vault address. Migration includes:
 *   - Calculate and reserve gas fees for migration transaction
 *   - Transfer tokens in batches (max 3 migrations per chain)
 *   - Update allowances for both vaults accordingly
 *
 * ### 6. Balance and Allowance Tracking
 * - Maintains per-chain, per-token balance states including:
 *   - Current balance and pending outgoing amounts
 *   - Reserved amounts for confirmed transfers
 *   - Target balances for rebalancing operations
 * - Vault-specific chain allowances track migration status and token limits
 *
 * ### 7. Access Control
 * - Only the Relay contract can invoke state-changing operations
 * - Administrative functions restricted to authorized roles
 * - Periphery contract provides chain configuration and fee calculations
 */
contract VaultManager is BaseImplementation, IVaultManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    uint256 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps
    uint256 private constant MAX_MIGRATION_AMOUNT = 3;
    bytes32 private constant NON_VAULT_KEY = bytes32(0x00);

    struct VaultFeeRate {
        uint24  ammVault;
        uint24  fromVault;
        uint24  toVault;

        uint24  balanceThreshold;    // balance fee calculation threshold
        int24  fixedFromBalance;    // a fixed balance fee for source chain transfer
        int24  fixedToBalance;      // the fixed balance fee for target chain transfer
        int24  minBalance;          // the min balance fee, it might be a negative value
        int24  maxBalance;          // the max balance fee

        uint96 reserved;            // reserved for future use
    }

    VaultFeeRate public vaultFeeRate;

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

    // not used for mintable token
    struct ChainTokenState {
        uint64 weight;              // chain weight for target balance
        uint128 balance;             // token balance
        uint128 pendingOut;          // token pendingOut balance
        uint128 reserved;           // reserved for transfer out
        uint128 target;             // target balance
    }

    struct TotalTokenState {
        uint64 totalWeight;
        uint128 totalBalance;
        uint128 totalPendingOut;
    }

    mapping(address => TotalTokenState) public totalStates;
    mapping(address => mapping(uint256 => ChainTokenState)) public chainStates;

    // token => amount
    mapping(address => uint256) public balanceFeeInfos;
    mapping(address => uint256) public vaultFeeInfos;

    address public securityFeeReceiver;

    event SetRelay(address _relay);
    event SetPeriphery(address _periphery);

    event FeeCollected(bytes32 indexed orderId, address token, uint256 vaultFee, uint256 ammVaultFee, uint256 balanceFee, bool incentive);

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
        // todo: update target balance
        // _updateTokenTargetBalance(token);
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

    //
    function chooseVault(TxItem memory txItem, bool withCall)
    external
    view
    override
    returns (bool choose, uint256 outAmount, bytes memory vault, GasInfo memory gasInfo)
    {
        bytes32 vaultKey;
        (choose, outAmount, vaultKey, gasInfo) = _chooseVault(txItem, withCall);
        if (vaultKey == NON_VAULT_KEY) {
            return (choose, outAmount, bytes(""), gasInfo);
        }

        return (choose, outAmount, vaultList[vaultKey].pubkey, gasInfo);
    }


    function checkVault(ChainType chainType, uint256, bytes calldata vault) external view returns (bool) {
        if (chainType == ChainType.CONTRACT) {
            // checked by source gateway contract for a contract chain
            return true;
        }
        bytes32 vaultKey = keccak256(vault);
        return (vaultKey == retiringVaultKey || vaultKey == activeVaultKey);
    }

    function getActiveVault() external view override returns (bytes memory) {
        return vaultList[activeVaultKey].pubkey;
    }

    function getRetiringVault() external view override returns (bytes memory) {
        if(retiringVaultKey != NON_VAULT_KEY) return vaultList[retiringVaultKey].pubkey;
        else return bytes("");
    }

    function getVaultTokenBalance(bytes memory vault, uint256 chain, address token) external view override returns(uint256 balance, uint256 pendingOut) {
        ChainType chainType = periphery.getChainType(chain);
        if(chainType == ChainType.CONTRACT) {
            ChainTokenState storage state =  chainStates[token][chain];
            balance = state.balance;
            pendingOut = state.pendingOut;
        } else {
            ChainAllowance storage allowance = vaultList[keccak256(vault)].chainAllowances[chain];
            balance = allowance.tokenAllowances;
            pendingOut = allowance.tokenPendingOutAllowances;
        }
    }


    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
    external
    view
    override
    returns (bool, uint256)
    {
        return _getBalanceFeeInfo(fromChain, toChain, token, amount);
    }

    function bridge(TxItem memory txItem, bytes memory fromVault, uint256 toChain, bool withCall) external override returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo) {
        VaultFeeRate memory feeRate = vaultFeeRate;
        uint256 amount = txItem.amount;

        FeeInfo memory feeInfo;
        uint256 ammFee = _getFee(txItem.amount, feeRate.ammVault);

        feeInfo.vaultFee = _getFee(txItem.amount, feeRate.toVault);

        (feeInfo.incentive, feeInfo.balanceFee) = _getBalanceFeeInfo(txItem.chain, toChain, txItem.token, txItem.amount);

        txItem.amount = _updateFeeAndAmount(txItem,feeInfo, ammFee);

        bytes32 vaultKey = keccak256(fromVault);
        _transferIn(txItem.chain, vaultKey, txItem);

        txItem.chain = toChain;
        txItem.chainType = periphery.getChainType(toChain);

        (choose, outAmount, vaultKey, gasInfo) = _chooseVault(txItem, withCall);
        if (vaultKey == NON_VAULT_KEY) {
            // no vault
            return (choose, amount, bytes(""), gasInfo);
        }

        _transferOut(txItem, vaultKey, gasInfo.estimateGas);

        return (choose, outAmount, vaultList[vaultKey].pubkey, gasInfo);
    }

    // vault fee, balance fee
    function transferIn(TxItem memory txItem, bytes memory fromVault, uint256) external override returns (uint256 outAmount) {
        VaultFeeRate memory feeRate = vaultFeeRate;

        FeeInfo memory feeInfo;
        feeInfo.vaultFee = _getFee(txItem.amount, feeRate.fromVault);
        // get a fix swapIn balance fee
        (feeInfo.incentive, feeInfo.balanceFee) = _getBalanceFee(txItem.amount, feeRate.fixedFromBalance);

        outAmount = _updateFeeAndAmount(txItem, feeInfo, 0);

        bytes32 vaultKey = keccak256(fromVault);
        _transferIn(txItem.chain, vaultKey, txItem);

        return txItem.amount;
    }

    function transferOut(TxItem memory txItem, uint256, bool withCall) external override returns (bool choose, uint256 outAmount, bytes memory vault, GasInfo memory gasInfo) {
        VaultFeeRate memory feeRate = vaultFeeRate;

        uint256 amount = txItem.amount;

        FeeInfo memory feeInfo;
        feeInfo.vaultFee = _getFee(txItem.amount, feeRate.toVault);
        // get a fix swapOut balance fee
        (feeInfo.incentive, feeInfo.balanceFee) = _getBalanceFee(txItem.amount, feeRate.fixedToBalance);

        txItem.amount = _updateFeeAndAmount(txItem, feeInfo, 0);

        bytes32 vaultKey;
        (choose, outAmount, vaultKey, gasInfo) = _chooseVault(txItem, withCall);
        if (vaultKey == NON_VAULT_KEY) {
            // no vault
            return (choose, amount, bytes(""), gasInfo);
        }

        _transferOut(txItem, vaultKey, gasInfo.estimateGas);

        return (choose, outAmount, vaultList[vaultKey].pubkey, gasInfo);
    }


    function migrate()
    external
    override
    onlyRelay
    returns (bool completed, TxItem memory txItem, GasInfo memory gasInfo, bytes memory fromVault, bytes memory toVault)
    {
        // check the retiring vault first
        if (retiringVaultKey == NON_VAULT_KEY) {
            // no retiring vault, no need migration
            return (true, txItem, gasInfo, bytes(""), bytes(""));
        }

        completed = true;
        Vault storage v = vaultList[retiringVaultKey];
        uint256[] memory chains = v.chains.values();
        for (uint256 i = 0; i < chains.length; i++) {
            uint256 chain = chains[i];
            if (v.chainAllowances[chain].migrationPending) {
                // migrating, continue to other chain migration
                continue;
            }
            txItem.chainType = periphery.getChainType(chain);
            txItem.chain = chain;

            // todo: how to get contract chain gas token, such as Polygon(POL), Kaia(KAIA)
            txItem.token = periphery.getChainGasToken(txItem.chain);
            (gasInfo.estimateGas, gasInfo.transactionRate, gasInfo.transactionSize) =
            periphery.getNetworkFeeInfoWithToken(txItem.token, chain,false);

            if (txItem.chainType == ChainType.CONTRACT) {
                vaultList[retiringVaultKey].chainAllowances[chain].migrationPending = true;

                // switch to active vault after migration when choosing vault
                vaultList[activeVaultKey].chains.add(chain);
                return (false, txItem, gasInfo, vaultList[retiringVaultKey].pubkey, vaultList[activeVaultKey].pubkey);
            }

            bool chainCompleted;
            (chainCompleted, txItem.amount) = _migrate(chain, txItem.token, gasInfo.estimateGas);

            // There is a chain migration that has not been completed. The migration status is incomplete.
            if (completed) {
                completed = chainCompleted;
            }
            if (txItem.amount == 0) {
                // migrating or have pending out tx
                continue;
            }

            return (completed, txItem, gasInfo, vaultList[retiringVaultKey].pubkey, vaultList[activeVaultKey].pubkey);
        }

        txItem.chain = 0;
        txItem.amount = 0;
        return (completed, txItem, gasInfo, bytes(""), bytes(""));
    }


    function chooseAndTransfer(TxItem memory txItem, bool withCall)
    external
    override
    onlyRelay
    returns (bool choose, uint256 outAmount, bytes memory vault, GasInfo memory gasInfo)
    {
        bytes32 vaultKey;
        (choose, outAmount, vaultKey, gasInfo) = _chooseVault(txItem, withCall);
        if (vaultKey == NON_VAULT_KEY) {
            return (choose, outAmount, bytes(""), gasInfo);
        }

        TotalTokenState storage totalState = totalStates[txItem.token];
        ChainTokenState storage chainState = chainStates[txItem.token][txItem.chain];

        if (txItem.chainType == ChainType.CONTRACT) {
            totalState.totalPendingOut += uint128(outAmount);

            chainState.pendingOut += uint128(outAmount);

            return (choose, outAmount, vaultList[vaultKey].pubkey, gasInfo);
        }

        totalState.totalPendingOut += uint128(outAmount + gasInfo.estimateGas);
        chainState.pendingOut += uint128(outAmount + gasInfo.estimateGas);

        vaultList[vaultKey].chains.add(txItem.chain);
        vaultList[vaultKey].chainAllowances[txItem.chain].tokenPendingOutAllowances += uint128(outAmount + gasInfo.estimateGas);

        return (choose, outAmount, vaultList[vaultKey].pubkey, gasInfo);
    }


    function refund(TxItem memory txItem, bytes memory vault)
    external
    onlyRelay
    returns (uint256 refundAmount, GasInfo memory gasInfo)
    {
        (gasInfo.estimateGas, gasInfo.transactionRate, gasInfo.transactionSize) =
        periphery.getNetworkFeeInfoWithToken(txItem.token, txItem.chain,false);

        if (txItem.amount <= gasInfo.estimateGas) {
            return (0, gasInfo);
        }

        refundAmount = txItem.amount - gasInfo.estimateGas;

        bytes32 vaultKey = keccak256(vault);
        totalStates[txItem.token].totalBalance += uint128(txItem.amount);

        ChainTokenState storage chainBalance = chainStates[txItem.token][txItem.chain];
        chainBalance.balance += uint128(txItem.amount);

        if (txItem.chainType == ChainType.CONTRACT) {
            totalStates[txItem.token].totalPendingOut += uint128(refundAmount);
            chainBalance.pendingOut += uint128(refundAmount);
        } else {
            // out amount + gas
            totalStates[txItem.token].totalPendingOut += uint128(txItem.amount);
            chainBalance.pendingOut += uint128(txItem.amount);

            vaultList[vaultKey].chainAllowances[txItem.chain].tokenAllowances += uint128(txItem.amount);
            vaultList[vaultKey].chainAllowances[txItem.chain].tokenPendingOutAllowances += uint128(txItem.amount);
        }

        // todo
        // _updateTokenTargetBalance(token);

        return (refundAmount, gasInfo);
    }

    function deposit(TxItem memory txItem, bytes memory vault)
    external
    onlyRelay
    {
        bytes32 vaultKey = keccak256(vault);
        uint128 amount = uint128(txItem.amount);

        totalStates[txItem.token].totalBalance += amount;

        ChainTokenState storage chainBalance = chainStates[txItem.token][txItem.chain];
        chainBalance.balance += amount;

        if (txItem.chainType != ChainType.CONTRACT) {
            vaultList[vaultKey].chainAllowances[txItem.chain].tokenAllowances += amount;
        }

        // todo
        // _updateTokenTargetBalance(token);
    }

    // tx out, remove liquidity or swap out
    function transferComplete(
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
        // todo
        // _updateTokenTargetBalance(token);
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

            _transferComplete(vaultKey, txItem, estimatedGas, usedGas);

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

    function _migrate(uint256 _chain, address token, uint256 gasFee) internal returns (bool completed, uint256 migrationAmount) {
        ChainAllowance storage p = vaultList[retiringVaultKey].chainAllowances[_chain];
        uint256 amount = p.tokenAllowances - p.tokenPendingOutAllowances;

        // todo: add min amount
        if (amount <= gasFee) {
            // no need migration
            if (p.tokenPendingOutAllowances > 0) {
                return (false, 0);
            }

            vaultList[retiringVaultKey].chains.remove(_chain);
            delete vaultList[retiringVaultKey].chainAllowances[_chain];

            // todo: emit event

            return (true, 0);
        }

        vaultList[retiringVaultKey].chainAllowances[_chain].migrationPending = true;

        migrationAmount = amount / (MAX_MIGRATION_AMOUNT - p.migrationIndex);
        if (migrationAmount <= gasFee || (amount - migrationAmount) <= gasFee) {
            migrationAmount = amount;
        }
        migrationAmount -= gasFee;
        p.migrationIndex++;

        p.tokenPendingOutAllowances += uint128(migrationAmount + gasFee);

        // todo: update total balance
        // todo: update pending out balance
        // ChainBalance storage chainBalance = tokenChainBalances[txItem.token][_chain];
        // chainBalance.pendingOut += gasFee;
        ChainTokenState storage chainBalance = chainStates[token][_chain];
        chainBalance.pendingOut += uint128(gasFee);
        return (false, migrationAmount);
    }


    function _chooseVault(TxItem memory txItem, bool withCall)
    internal
    view
    returns (bool, uint256 outAmount, bytes32 vaultKey, GasInfo memory gasInfo)
    {
        (gasInfo.estimateGas, gasInfo.transactionRate, gasInfo.transactionSize) =
        periphery.getNetworkFeeInfoWithToken(txItem.token, txItem.chain,withCall);

        if (txItem.amount <= gasInfo.estimateGas) {
            return (false, txItem.amount, NON_VAULT_KEY, gasInfo);
        }

        outAmount = txItem.amount - gasInfo.estimateGas;

        uint128 allowance;
        if (txItem.chainType == ChainType.CONTRACT) {
            ChainTokenState storage chainBalance = chainStates[txItem.token][txItem.chain];
            allowance = chainBalance.balance - chainBalance.pendingOut;
            if (allowance < outAmount) return (false, txItem.amount, NON_VAULT_KEY, gasInfo);
            if (vaultList[activeVaultKey].chains.contains(txItem.chain)) {
                return (true, outAmount, activeVaultKey, gasInfo);
            } else {
                // not start migration, using retiring vault key
                return (true, outAmount, retiringVaultKey, gasInfo);
            }
        }
        // non-contract chain
        // choose active vault first, if not match, choose retiring vault
        ChainAllowance storage p = vaultList[activeVaultKey].chainAllowances[txItem.chain];
        allowance = p.tokenAllowances - p.tokenPendingOutAllowances;
        if (allowance >= txItem.amount) {
            return (true, outAmount, activeVaultKey, gasInfo);
        }

        p = vaultList[retiringVaultKey].chainAllowances[txItem.chain];
        allowance = p.tokenAllowances - p.tokenPendingOutAllowances;
        if (allowance >= txItem.amount) {
            return (true, outAmount, retiringVaultKey, gasInfo);
        }

        return (false, txItem.amount, NON_VAULT_KEY, gasInfo);
    }

    function _getBalanceFeeInfo(uint256 fromChain, uint256 toChain, address token, uint256 amount)
    internal
    view
    returns (bool, uint256)
    {

    }


    function _getFee(uint256 amount, uint256 feeRate) internal pure returns (uint256 fee) {
        if (feeRate == 0) {
            return 0;
        }
        fee = amount * feeRate / MAX_RATE_UNIT;
    }

    function _getBalanceFee(uint256 amount, int24 feeRate) internal pure returns (bool incentive, uint256 fee) {
        incentive = (feeRate > 0);
        uint256 rate = incentive ? uint256(int256(feeRate)) : uint256(int256(-feeRate));
        fee = _getFee(amount, rate);
    }

    function _updateFeeAndAmount(TxItem memory txItem, FeeInfo memory feeInfo, uint256 ammVaultFee) internal returns (uint256 outAmount) {
        uint256 balanceFee = feeInfo.balanceFee;
        vaultFeeInfos[txItem.token] += feeInfo.vaultFee;
        if (feeInfo.incentive) {
            if (feeInfo.balanceFee >= balanceFeeInfos[txItem.token]) {
                balanceFee = balanceFeeInfos[txItem.token];
                outAmount = txItem.amount + balanceFee - feeInfo.vaultFee;
                balanceFeeInfos[txItem.token] = 0;
            } else {
                balanceFeeInfos[txItem.token] -= feeInfo.balanceFee;
                outAmount = txItem.amount + feeInfo.balanceFee - feeInfo.vaultFee;
            }
        } else {
            balanceFeeInfos[txItem.token] += feeInfo.balanceFee;
            outAmount = txItem.amount - feeInfo.balanceFee - feeInfo.vaultFee;
        }

        emit FeeCollected(txItem.orderId, txItem.token, feeInfo.vaultFee, ammVaultFee, balanceFee, feeInfo.incentive);
    }

    // update source vault amount
    function _transferIn(uint256 fromChain, bytes32 vaultKey, TxItem memory txItem) internal {
        TotalTokenState storage totalState = totalStates[txItem.token];
        ChainTokenState storage chainState = chainStates[txItem.token][fromChain];

        uint128 amount = uint128(txItem.amount);
        totalState.totalBalance += amount;

        chainState.balance += amount;

        if (txItem.chainType != ChainType.CONTRACT) {
            vaultList[vaultKey].chainAllowances[fromChain].tokenAllowances += amount;
        }
    }

    // update target vault pending amount, include gas info
    function _transferOut(TxItem memory txItem, bytes32 vaultKey, uint256 estimateGas) internal {
        TotalTokenState storage totalState = totalStates[txItem.token];
        ChainTokenState storage chainState = chainStates[txItem.token][txItem.chain];

        uint128 outAmount = uint128(txItem.amount);
        if (txItem.chainType == ChainType.CONTRACT) {
            totalState.totalPendingOut += outAmount;

            chainState.pendingOut += outAmount;
        } else {
            outAmount = uint128(txItem.amount + estimateGas);
            totalState.totalPendingOut += outAmount;
            chainState.pendingOut += outAmount;

            vaultList[vaultKey].chains.add(txItem.chain);
            vaultList[vaultKey].chainAllowances[txItem.chain].tokenPendingOutAllowances += outAmount;
        }
    }

    // update target vault amount
    function _transferComplete(bytes32 vaultKey, TxItem memory txItem, uint256 relayGasUsed, uint256 relayGasEstimated) internal {
        TotalTokenState storage totalState = totalStates[txItem.token];
        ChainTokenState storage chainState = chainStates[txItem.token][txItem.chain];

        if (txItem.chainType != ChainType.CONTRACT) {
            uint128 amount = uint128(txItem.amount + relayGasUsed);

            totalState.totalBalance -= amount;
            chainState.balance -= amount;
            vaultList[vaultKey].chainAllowances[txItem.chain].tokenAllowances -= amount;

            amount = uint128(txItem.amount + relayGasEstimated);
            totalState.totalPendingOut -= amount;
            chainState.pendingOut -= amount;
            vaultList[vaultKey].chainAllowances[txItem.chain].tokenPendingOutAllowances -= amount;
        } else {
            uint128 amount = uint128(txItem.amount);
            totalState.totalBalance -= amount;
            totalState.totalPendingOut -= amount;

            chainState.balance -= amount;
            chainState.pendingOut -= amount;
        }
    }


}
