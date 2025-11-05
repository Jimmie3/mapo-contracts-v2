// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./libs/Utils.sol";
import "./interfaces/IVaultToken.sol";
import "./interfaces/IRegistry.sol";

import {IVaultManager} from "./interfaces/IVaultManager.sol";

import {ChainType, TxItem, GasInfo} from "./libs/Types.sol";
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

    uint24 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps

    int24 constant MAX_BALANCE_CHANGE = 600000;         // 60%
    int24 constant MIN_BALANCE_CHANGE = -600000;        // -60%

    uint128 private constant MAX_MIGRATION_AMOUNT = 3;
    bytes32 private constant NON_VAULT_KEY = bytes32(0x00);

    uint256 public immutable selfChainId = block.chainid;

    struct FeeInfo {
        uint256 vaultFee;
        uint256 balanceFee;
        bool incentive;
    }

    struct VaultFeeRate {
        uint24  ammVault;           // the fee to vault when bridging
        uint24  fromVault;          // the fee to swap in token vault
        uint24  toVault;            // the fee to bridge/swap out token vault

        uint24 balanceThreshold;    // balance fee calculation threshold

        int24  fixedFromBalance;    // a fixed balance fee for source chain transfer, mostly is zero
        int24  fixedToBalance;      // the fixed balance fee for target chain transfer
        int24  minBalance;          // the min balance fee, it might be a negative value
        int24  maxBalance;          // the max balance fee, it might be a negative value

        uint96 reserved;            // reserved for future use
    }

    struct ChainTokenVault {
        uint128 balance;
        uint128 pendingOut;

        bool isAdded;           // whether token has been added to chain vault
        uint8 migrationIndex;
    }

    // non-contract chain vault
    struct ChainVault {
        // todo: only support native token now
        // the native token will be the first one, and will be migrated at last
        address[] tokens;
        mapping(address => ChainTokenVault) tokenVaults;
    }

    struct Vault {
        EnumerableSet.UintSet chains;
        bytes pubkey;
        // set true after start a migration, reset after migration txOut on relay chain.
        mapping(uint256 chain => bool) isMigrating;
        mapping(uint256 chain => ChainVault) chainVaults;
    }

    // not used for mintable token
    struct TokenChainState {
        uint24 weight;              // chain weight for target balance
        uint128 minAmount;          // minimum migration amount
        uint128 reserved;           // reserved for transfer out
        uint128 maxCredit;          // reserved
        int128 balance;             // token balance
        uint128 pendingOut;          // token pendingOut balance
    }

    struct TokenState {
        uint24 deltaSMax;
        uint24 totalWeight;
        uint128 balance;
        uint128 pendingOut;

        mapping(uint256 => TokenChainState) chainStates;
    }

    address public relay;
    IPeriphery public periphery;

    VaultFeeRate public vaultFeeRate;

    // only one active vault and one retiring vault at a time
    // after migration, only one active vault, no retiring vault
    bytes32 public activeVaultKey;
    bytes32 public retiringVaultKey;

    mapping(bytes32 => Vault) private vaultList;

    EnumerableSet.UintSet private chainList;        // all support chains

    // token => vaultToken
    EnumerableMap.AddressToAddressMap private tokenList;

    mapping(address => TokenState) public tokenStates;

    // token => amount
    mapping(address => uint256) public balanceFees;

    // reserved for migration gas
    mapping(address => uint256) public reservedFees;

    event SetRelay(address _relay);
    event SetPeriphery(address _periphery);

    event FeeCollected(bytes32 indexed orderId, address token, uint256 vaultFee, uint256 ammVaultFee, uint256 balanceFee, bool incentive);

    event UpdateTokenWeight(address indexed token, uint256 chain, uint24 weight);
    event UpdateBalanceIndicator(address indexed token, uint24 totalWeight, uint24 deltaMax);

    event UpdateVaultFeeRate(VaultFeeRate _vaultFeeRate);

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

    function updateVaultFeeRate(VaultFeeRate calldata _vaultFeeRate) external restricted {
        require(_vaultFeeRate.ammVault < MAX_RATE_UNIT);
        require(_vaultFeeRate.fromVault < MAX_RATE_UNIT);
        require(_vaultFeeRate.toVault < MAX_RATE_UNIT);
        vaultFeeRate = _vaultFeeRate;
        emit UpdateVaultFeeRate(_vaultFeeRate);
    }

    function updateTokenWeights(address token, uint256[] memory chains, uint256[] memory weights) external restricted {
        uint256 len = chains.length;
        require(len == weights.length);
        uint256 i;
        uint256 chain;

        TokenState storage tokenState = tokenStates[token];
        for (i = 0; i < len; i++) {
            chain = chains[i];

            TokenChainState storage chainState = tokenState.chainStates[chain];
            uint24 weight = uint24(weights[i]);
            tokenState.totalWeight = tokenState.totalWeight - chainState.weight + weight;
            chainState.weight = weight;

            emit UpdateTokenWeight(token, chain, weight);
        }

        _updateBalanceIndicator(token);
    }

    function registerToken(address token, address vaultToken) external restricted {
        // todo: check vault token
        tokenList.set(token, vaultToken);
    }


    // S_max represents the worst possible imbalance scenario where all assets are concentrated on a single chain.
    // It serves as the upper bound for normalization.
    //
    // For a given weight distribution, S_max occurs when:
    //- One chain k has all assets: Vₖ = Vₜ (thus rₖ = 1/Wₖ - 1)
    //- All other chains are empty: Vᵢ = 0 for i ≠ k (thus rᵢ = -1)
    // Wₜ = 1, S_k = (1 - Wₖ)/Wₖ
    function _updateBalanceIndicator(address _token) internal {
        uint24 wmin = MAX_RATE_UNIT;
        uint256 length = chainList.length();

        TokenState storage tokenState = tokenStates[_token];
        for (uint256 i = 0; i < length; i++) {
            uint256 chain = chainList.at(i);
            uint24 w = tokenState.chainStates[chain].weight;
            if (w == 0) {
                continue;
            }
            if (w < wmin) {
                wmin = w;
            }
        }

        tokenState.deltaSMax = (tokenState.totalWeight - wmin) / wmin;

        emit UpdateBalanceIndicator(_token, tokenState.totalWeight, tokenState.deltaSMax);
    }


    function rotate(bytes memory retiringVault, bytes memory activeVault) external override onlyRelay {
        // todo: check retiring vault
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
        if (retiringVaultKey != NON_VAULT_KEY) revert Errs.migration_not_completed();

        // check all balance
        uint256 length = tokenList.length();
        for (uint256 i = 0; i < length; i++) {
            (address token, ) = tokenList.at(i);
            TokenState storage s = tokenStates[token];
            if (s.balance > 0) revert Errs.token_allowance_not_zero();
            if (s.chainStates[chain].weight > 0) {
                s.totalWeight -= s.chainStates[chain].weight;

                _updateBalanceIndicator(token);
            }
            delete s.chainStates[chain];
        }

        ChainVault storage v = vaultList[activeVaultKey].chainVaults[chain];
        length = v.tokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = v.tokens[i];
            if (v.tokenVaults[token].balance > 0) revert Errs.token_allowance_not_zero();
            delete v.tokenVaults[token];
        }
        delete v.tokens;

        delete vaultList[activeVaultKey].chainVaults[chain];
        delete vaultList[activeVaultKey].isMigrating[chain];
        vaultList[activeVaultKey].chains.remove(chain);

        chainList.remove(chain);

        // todo: emit event
    }

    function checkMigration() external view override returns (bool completed, uint256 toMigrateChain) {
        // check the retiring vault first
        if (retiringVaultKey == NON_VAULT_KEY) {
            // no retiring vault, no need migration
            return (true, 0);
        }

        Vault storage v = vaultList[retiringVaultKey];
        uint256 length = v.chains.length();
        for (uint256 i = 0; i < length; i++) {
            uint256 chain = v.chains.at(i);
            if (v.isMigrating[chain]) {
                // migrating, continue to other chain migration
                continue;
            }

            return (false, chain);
        }

        if (v.chains.length() > 0) {
            return (false, 0);
        }

        return (true, 0);
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
        if (retiringVaultKey != NON_VAULT_KEY) return vaultList[retiringVaultKey].pubkey;
        else return bytes("");
    }

   function getVaultTokenBalance(bytes memory vault, uint256 chain, address token) external view returns(int256 balance, uint256 pendingOut) {
       ChainType chainType = periphery.getChainType(chain);
       if(chainType == ChainType.CONTRACT) {
            TokenChainState storage state =  tokenStates[token].chainStates[chain];
            balance = state.balance;
            pendingOut = state.pendingOut;
       } else {
            ChainTokenVault storage chainTokenVault = vaultList[keccak256(vault)].chainVaults[chain].tokenVaults[token];
            balance = int128(chainTokenVault.balance);
            pendingOut = chainTokenVault.pendingOut;
       }

   }


    function getBalanceFee(uint256 fromChain, uint256 toChain, address token, uint256 amount)
    external
    view
    override
    returns (bool, uint256)
    {
        return _getBalanceFeeInfo(fromChain, toChain, token, amount, false, false);
    }

    function bridge(TxItem memory txItem, bytes memory fromVault, uint256 toChain, bool withCall) external override returns (bool choose, uint256 outAmount, bytes memory toVault, GasInfo memory gasInfo) {
        VaultFeeRate memory feeRate = vaultFeeRate;
        uint256 amount = txItem.amount;

        FeeInfo memory feeInfo;
        uint256 ammFee = _getFee(txItem.amount, feeRate.ammVault);

        feeInfo.vaultFee = _getFee(txItem.amount, feeRate.toVault);

        (feeInfo.incentive, feeInfo.balanceFee) = _getBalanceFeeInfo(txItem.chain, toChain, txItem.token, txItem.amount, false, false);

        txItem.amount = _collectVaultAndBalanceFee(txItem,feeInfo, ammFee);

        bytes32 vaultKey = keccak256(fromVault);
        _transferIn(vaultKey, txItem);

        txItem.chain = toChain;
        txItem.chainType = periphery.getChainType(toChain);

        (vaultKey, outAmount, gasInfo) = _chooseVault(txItem, withCall);
        if (vaultKey == NON_VAULT_KEY) {
            // no vault
            return (false, amount, bytes(""), gasInfo);
        }

        _transferOut(vaultKey, txItem,  uint128(outAmount), gasInfo.estimateGas);

        return (true, outAmount, vaultList[vaultKey].pubkey, gasInfo);
    }

    // collect transfer in fee
    // update vault balance
    function transferIn(TxItem memory txItem, bytes memory fromVault, uint256) external override returns (uint256 outAmount) {
        VaultFeeRate memory feeRate = vaultFeeRate;

        FeeInfo memory feeInfo;
        feeInfo.vaultFee = _getFee(txItem.amount, feeRate.fromVault);
        // get a fix swapIn balance fee
        (feeInfo.incentive, feeInfo.balanceFee) = _getBalanceFee(txItem.amount, feeRate.fixedFromBalance);

        outAmount = _collectVaultAndBalanceFee(txItem, feeInfo, 0);

        bytes32 vaultKey = keccak256(fromVault);
        _transferIn(vaultKey, txItem);

        return txItem.amount;
    }

    function transferOut(TxItem memory txItem, uint256, bool withCall) external override returns (bool choose, uint256 outAmount, bytes memory vault, GasInfo memory gasInfo) {
        VaultFeeRate memory feeRate = vaultFeeRate;

        uint256 amount = txItem.amount;

        FeeInfo memory feeInfo;
        feeInfo.vaultFee = _getFee(txItem.amount, feeRate.toVault);
        // get a fix swapOut balance fee
        (feeInfo.incentive, feeInfo.balanceFee) = _getBalanceFee(txItem.amount, feeRate.fixedToBalance);

        txItem.amount = _collectVaultAndBalanceFee(txItem, feeInfo, 0);

        bytes32 vaultKey;
        (vaultKey, outAmount, gasInfo) = _chooseVault(txItem, withCall);
        if (vaultKey == NON_VAULT_KEY) {
            // no vault
            return (false, amount, bytes(""), gasInfo);
        }

        _transferOut(vaultKey, txItem, uint128(outAmount), gasInfo.estimateGas);

        return (true, outAmount, vaultList[vaultKey].pubkey, gasInfo);
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
            if (v.isMigrating[chain]) {
                // migrating, continue to other chain migration
                continue;
            }
            txItem.chainType = periphery.getChainType(chain);
            txItem.chain = chain;

            gasInfo = periphery.getNetworkFeeInfo(chain,false);

            if (txItem.chainType == ChainType.CONTRACT) {
                v.isMigrating[chain] = true;

                // switch to active vault after migration start when choosing vault
                if(chain != selfChainId) vaultList[activeVaultKey].chains.add(chain);
                return (false, txItem, gasInfo, vaultList[retiringVaultKey].pubkey, vaultList[activeVaultKey].pubkey);
            }

            bool chainCompleted;
            (chainCompleted, txItem.token, txItem.amount) = _noncontractMigrate(chain, gasInfo);

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


    function refund(TxItem memory txItem, bytes memory vault, bool fromRetiredVault)
    external
    onlyRelay
    returns (uint256, GasInfo memory)
    {
        GasInfo memory gasInfo = periphery.getNetworkFeeInfoWithToken(txItem.token, txItem.chain,false);
        if (fromRetiredVault) {
            if (txItem.amount <= gasInfo.estimateGas) {
                return (0, gasInfo);
            }
            return ((txItem.amount - gasInfo.estimateGas), gasInfo);
        }

        bytes32 vaultKey = keccak256(vault);

        _transferIn(vaultKey, txItem);
        if (txItem.amount <= gasInfo.estimateGas) {
            // out of gas, save as reserved fee and return
            reservedFees[txItem.token] += txItem.amount;
            return (0, gasInfo);
        }

        uint128 refundAmount = uint128(txItem.amount) - gasInfo.estimateGas;
        _transferOut(vaultKey, txItem, refundAmount, gasInfo.estimateGas);

        return (refundAmount, gasInfo);
    }


    function deposit(TxItem memory txItem, bytes memory vault)
    external
    onlyRelay
    {
        bytes32 vaultKey = keccak256(vault);
        _transferIn(vaultKey, txItem);

        IVaultToken vaultToken = IVaultToken(tokenList.get(txItem.token));

        // todo: check maximum deposit amount

        vaultToken.deposit(txItem.amount, txItem.to);
    }

    function redeem(address _vaultToken, uint256 _share, address _owner, address _receiver) external override onlyRelay  returns (uint256)  {

        IVaultToken vaultToken = IVaultToken(_vaultToken);
        address token = vaultToken.asset();
        uint256 amount = vaultToken.redeem(_share, _receiver, _owner);

        // todo: collect balance fee
        tokenStates[token].balance -= uint128(amount);
        tokenStates[token].chainStates[selfChainId].balance -= _toInt128(amount);
        // _transferOut(activeVaultKey, txItem, uint128(txItem.amount), 0);

        return amount;
    }

    // tx out, remove liquidity or swap out
    function transferComplete(TxItem memory txItem, bytes memory vault, uint256 relayGasUsed, uint256 relayGasEstimated) external override onlyRelay returns (uint256 gas, uint256 amount) {
        bytes32 vaultKey = keccak256(vault);

        if (vaultKey != retiringVaultKey || vaultKey != activeVaultKey) revert Errs.invalid_vault();

        _transferComplete(vaultKey, txItem, uint128(relayGasUsed), uint128(relayGasEstimated));
        if (txItem.chainType == ChainType.CONTRACT) {
            return (relayGasEstimated, txItem.amount);
        }
        // save not used gas
        // todo: check usedGas > estimatedGas
        reservedFees[txItem.token] += (relayGasEstimated - relayGasUsed);

        return (0, (txItem.amount + relayGasUsed));
    }


    function migrationComplete(TxItem memory txItem, bytes memory fromVault, bytes memory toVault, uint256 estimatedGas, uint256 usedGas)
    external
    override
    onlyRelay returns (uint256 gas, uint256 amount)
    {
        bytes32 vaultKey = keccak256(fromVault);
        bytes32 targetVaultKey = keccak256(toVault);
        if (vaultKey != retiringVaultKey || targetVaultKey != activeVaultKey) revert Errs.invalid_vault();

        if (txItem.chainType == ChainType.CONTRACT) {
            delete vaultList[vaultKey].chainVaults[txItem.chain];
            delete vaultList[vaultKey].isMigrating[txItem.chain];
            vaultList[vaultKey].chains.remove(txItem.chain);
            gas = estimatedGas;
        } else {
            vaultList[vaultKey].isMigrating[txItem.chain] = false;
            _transferComplete(vaultKey, txItem, uint128(usedGas), uint128(estimatedGas));
            _transferIn(targetVaultKey, txItem);
            amount = usedGas;
        }

        // use reserved fee to cover migration gas
        if (reservedFees[txItem.token] >= gas) {
            reservedFees[txItem.token] -= gas;
        } else {
            uint256 decreased = gas - reservedFees[txItem.token];
            reservedFees[txItem.token] = 0;

            // use vault token to cover migration gas
            // will incentive from relay chain later
            IVaultToken vaultToken = IVaultToken(tokenList.get(txItem.token));
            vaultToken.decreaseVault(decreased);
        }
    }

    function _addVaultToken(bytes32 vaultKey, uint256 chain, address token) internal {
        ChainVault storage cv = vaultList[vaultKey].chainVaults[chain];

        if (cv.tokenVaults[token].isAdded) {
            return;
        }
        if (cv.tokens.length == 0) {
            // add native token first
            address nativeToken = periphery.getChainGasToken(chain);
            cv.tokens.push(nativeToken);
            cv.tokenVaults[nativeToken].isAdded = true;
            if (token == nativeToken) {
                return;
            }
        }
        // todo: support alt token on non-contract
        // cv.tokens.push(token);
        // cv.tokenVaults[token].isAdded = true;
    }

    // return:
    //      true: completed
    //      false: not completed
    //              amount > 0: new migration
    //              amount = 0: no migration
    function _noncontractMigrate(uint256 _chain, GasInfo memory gasInfo) internal returns (bool completed, address token, uint256 amount) {
        ChainVault storage v = vaultList[retiringVaultKey].chainVaults[_chain];
        uint256 tokenLength = v.tokens.length;
        while (tokenLength > 0) {
            token = v.tokens[tokenLength - 1];
            if (token != gasInfo.gasToken) {
                // todo: support multi tokens migration for non-contract chain
                v.tokens.pop();
                delete v.tokenVaults[token];
                tokenLength -= 1;

                continue;
            }

            ChainTokenVault storage tokenBalance = v.tokenVaults[token];
            uint128 minAmount = tokenStates[token].chainStates[_chain].minAmount;
            uint128 estimateGas = uint128(gasInfo.estimateGas);
            if (minAmount < gasInfo.estimateGas) { minAmount = estimateGas;}
            uint128 available = tokenBalance.balance - tokenBalance.pendingOut;
            if (available <= minAmount) {
                // no need migration
                if (tokenBalance.pendingOut > 0) {
                    // waiting pending out tx
                    return (false, token, 0);
                }

                v.tokens.pop();
                delete v.tokenVaults[token];
                tokenLength -= 1;

                continue;
            }

            vaultList[retiringVaultKey].isMigrating[_chain] = true;

            uint128 migrationAmount = available / (MAX_MIGRATION_AMOUNT - tokenBalance.migrationIndex);
            if (migrationAmount <= minAmount || (available - migrationAmount) <= minAmount) {
                migrationAmount = available;
            }
            migrationAmount -= estimateGas;

            tokenBalance.migrationIndex++;
            TxItem memory txItem;
            txItem.chainType = ChainType.NON_CONTRACT;
            txItem.chain = _chain;
            txItem.token = token;
            _transferOut(retiringVaultKey, txItem, migrationAmount, estimateGas);

            return (false, token, migrationAmount);
        }

        // token length == 0
        vaultList[retiringVaultKey].chains.remove(_chain);
        delete vaultList[retiringVaultKey].chainVaults[_chain];
        delete vaultList[retiringVaultKey].isMigrating[_chain];

        // todo: emit event
        return (true, token, 0);
    }

    function _chooseVault(TxItem memory txItem, bool withCall)
    internal
    view
    returns (bytes32 vaultKey, uint256 outAmount, GasInfo memory gasInfo)
    {    
        if(txItem.chain == selfChainId) {
            return (activeVaultKey, txItem.amount, gasInfo);
        }
        // todo: support alt token on non-contract chain
        //      get gas for gas token
        gasInfo = periphery.getNetworkFeeInfoWithToken(txItem.token, txItem.chain,withCall);

        if (txItem.amount <= gasInfo.estimateGas) {
            return (NON_VAULT_KEY, txItem.amount, gasInfo);
        }

        outAmount = txItem.amount - gasInfo.estimateGas;

        uint128 allowance;
        if (txItem.chainType == ChainType.CONTRACT) {
            TokenChainState storage chainState = tokenStates[txItem.token].chainStates[txItem.chain];
            if(chainState.balance < 0) return (NON_VAULT_KEY, txItem.amount, gasInfo);
            allowance = uint128(chainState.balance) - chainState.pendingOut;
            if (allowance < outAmount) return (NON_VAULT_KEY, txItem.amount, gasInfo);
            if (vaultList[activeVaultKey].chains.contains(txItem.chain)) {
                return (activeVaultKey, outAmount, gasInfo);
            } else {
                // not start migration, using retiring vault key
                return (retiringVaultKey, outAmount, gasInfo);
            }
        }
        // non-contract chain
        // choose active vault first, if not match, choose retiring vault
        if (_checkVaultAllowance(activeVaultKey, txItem)) {
            return (activeVaultKey, outAmount, gasInfo);
        } else if (_checkVaultAllowance(retiringVaultKey, txItem)) {
            return (retiringVaultKey, outAmount, gasInfo);
        }

        return (NON_VAULT_KEY, txItem.amount, gasInfo);
    }

    function _checkVaultAllowance(bytes32 vaultKey, TxItem memory txItem) internal view returns (bool) {
        ChainTokenVault storage p = vaultList[vaultKey].chainVaults[txItem.chain].tokenVaults[txItem.token];
        uint128 allowance = p.balance - p.pendingOut;
        if (allowance >= txItem.amount) {
            return true;
        } else {
            return false;
        }
    }

    function _getBalanceChangePercent(uint256 fromChain, uint256 toChain, address token, uint256 amount) internal view returns (int24 deltaPercent) {
        uint256 total = tokenStates[token].balance;
        // ΔS = [2a(vₓ×wᵧ - vᵧ×wₓ) + a²(wₓ + wᵧ)] / (wₓ×wᵧ×Tᵥ²)
        //    = [2avₓ×wᵧ + a²(wₓ + wᵧ) - 2avᵧ×wₓ ] / (wₓ×wᵧ×Tᵥ²)
        TokenChainState memory x = tokenStates[token].chainStates[fromChain];
        TokenChainState memory y = tokenStates[token].chainStates[toChain];

        int24 deltaS;
        uint256 totalWeight = tokenStates[token].totalWeight;

        // 2avₓ×wᵧ + a²(wₓ + wᵧ)
        uint256 s1 = 2 * amount * uint128(x.balance) * y.weight + amount * amount * (x.weight + y.weight);
        // 2avᵧ×wₓ
        uint256 s2 = 2 * amount * uint128(y.balance) * x.weight;
        if (s1 > s2) {
            uint256 delta = _divUint256(((s1 - s2) * totalWeight), (x.weight * y.weight * total * total));
            deltaS = int24(int256(delta));
        } else {
            uint256 delta = _divUint256(((s2 - s1) * totalWeight), (x.weight * y.weight * total * total));
            deltaS = 0 - int24(int256(delta));
        }
        int24 deltaSMax = int24(tokenStates[token].deltaSMax);
        return _divInt24(deltaS * int24(MAX_RATE_UNIT), deltaSMax);
    }

    function _getBalanceFeeInfo(uint256 fromChain, uint256 toChain, address token, uint256 amount, bool isSwapIn, bool isSwapOut)
    internal
    view
    returns (bool incentive, uint256 fee)
    {
        VaultFeeRate memory feeRate = vaultFeeRate;

        if (isSwapIn) {
            // get a fix swapIn balance fee
            return _getBalanceFee(amount, feeRate.fixedFromBalance);
        }
        if (isSwapOut) {
            // get a fix swapOut balance fee
            return _getBalanceFee(amount, feeRate.fixedToBalance);
        }

        uint256 total = tokenStates[token].balance;
        // To save gas, when the cross-chain amount is less than a certain threshold (e.g., 0.1% of total vault),
        // instead of directly calculating balance fee/incentive, charge a fixed fee
        if (amount * MAX_RATE_UNIT <= total * feeRate.balanceThreshold) {
            return _getBalanceFee(amount, (feeRate.fixedFromBalance + feeRate.fixedToBalance));
        }

        int24 rate;
        int24 deltaPercent = _getBalanceChangePercent(fromChain, toChain, token, amount);
        if (deltaPercent >= MAX_BALANCE_CHANGE) {
            rate = feeRate.maxBalance;
        } else if (deltaPercent <= MIN_BALANCE_CHANGE) {
            rate = feeRate.minBalance;
        } else {
            rate = _divInt24(deltaPercent * (MAX_BALANCE_CHANGE - MIN_BALANCE_CHANGE), ((feeRate.maxBalance - feeRate.minBalance) + feeRate.minBalance));
        }

        return _getBalanceFee(amount, rate);
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

    function _collectVaultAndBalanceFee(TxItem memory txItem, FeeInfo memory feeInfo, uint256 ammVaultFee) internal returns (uint256 outAmount) {
        uint256 balanceFee = feeInfo.balanceFee;
        IVaultToken vaultToken = IVaultToken(tokenList.get(txItem.token));
        // todo: check vault token exist
        vaultToken.increaseVault(feeInfo.vaultFee);

        if (feeInfo.incentive) {
            if (feeInfo.balanceFee >= balanceFees[txItem.token]) {
                balanceFee = balanceFees[txItem.token];
                outAmount = txItem.amount + balanceFee - feeInfo.vaultFee;
                balanceFees[txItem.token] = 0;
            } else {
                balanceFees[txItem.token] -= feeInfo.balanceFee;
                outAmount = txItem.amount + balanceFee - feeInfo.vaultFee;
            }
        } else {
            balanceFees[txItem.token] += feeInfo.balanceFee;
            outAmount = txItem.amount - feeInfo.balanceFee - feeInfo.vaultFee;
        }

        emit FeeCollected(txItem.orderId, txItem.token, feeInfo.vaultFee, ammVaultFee, balanceFee, feeInfo.incentive);
    }


    // add token balance
    // add chain and token vault
    function _transferIn(bytes32 vaultKey, TxItem memory txItem) internal {
        if(txItem.chain != selfChainId) vaultList[vaultKey].chains.add(txItem.chain);
        uint128 amount = uint128(txItem.amount);

        tokenStates[txItem.token].balance += amount;
        tokenStates[txItem.token].chainStates[txItem.chain].balance += int128(amount);

        if (txItem.chainType != ChainType.CONTRACT) {
            _addVaultToken(vaultKey, txItem.chain, txItem.token);
            vaultList[vaultKey].chainVaults[txItem.chain].tokenVaults[txItem.token].balance += amount;
        }
    }

    // update target vault pending amount, include gas info
    function _transferOut(bytes32 vaultKey, TxItem memory txItem, uint128 outAmount, uint128 estimateGas) internal {
        // todo: support alt chain on non-contract chain
        uint128 total = (txItem.chainType == ChainType.CONTRACT) ? outAmount : (outAmount + estimateGas);

        tokenStates[txItem.token].pendingOut += total;
        tokenStates[txItem.token].chainStates[txItem.chain].pendingOut += total;

        if (txItem.chainType != ChainType.CONTRACT) {
            vaultList[vaultKey].chainVaults[txItem.chain].tokenVaults[txItem.token].pendingOut += total;
        }
    }

    // update balance, remove pending
    function _transferComplete(bytes32 vaultKey, TxItem memory txItem, uint128 usedGas, uint128 estimateGas) internal{
        TokenState storage totalState = tokenStates[txItem.token];
        TokenChainState storage chainState = tokenStates[txItem.token].chainStates[txItem.chain];

        uint128 amount = uint128(txItem.amount);
        if (txItem.chainType == ChainType.CONTRACT) {
            totalState.balance -= amount;
            totalState.pendingOut -= amount;

            chainState.balance -= int128(amount);
            chainState.pendingOut -= amount;

            return;
        }
        // add tx gas cost for non contract chain
        ChainTokenVault storage tokenVault = vaultList[vaultKey].chainVaults[txItem.chain].tokenVaults[txItem.token];
        // todo: support alt token
        //       update gas token balance with usedGas
        //       update alt token balance with amount
        totalState.balance -= (amount + usedGas);
        totalState.pendingOut -= (amount + estimateGas);

        chainState.balance -= int128(amount + usedGas);
        chainState.pendingOut -= (amount + estimateGas);

        tokenVault.balance -= (amount + usedGas);
        tokenVault.pendingOut -= (amount + estimateGas);
    }

    function _divUint256(uint256 a, uint256 b) internal pure returns(uint256) {
        if(b == 0) return 0;
        return a / b;
    }
    
    function _divInt24(int24 a, int24 b) internal pure returns(int24) {
        if(b == 0) return 0;
        return a / b;
    }

    function _toInt128(uint256 a) internal pure returns(int128) {
        return int128(int256(a));
    }
}
