# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Structure

This is MAP Protocol contracts repository with a multi-chain architecture:

- `maintainer/` - TSS maintainer system (see `maintainer/CLAUDE.md` for details)
- `protocol/` - Core protocol contracts (see `protocol/CLAUDE.md` for details)
- `common/` - Shared contracts library (@mapprotocol/common-contracts npm package)
- `evm/` - EVM-specific implementations
- `solana/` - Solana blockchain implementations

Each module has its own `CLAUDE.md` with detailed documentation.

## Development Commands

### Working Directory Commands

For `maintainer/` directory:

### Build Commands
- `npm run build` or `forge build` - Build contracts using Foundry
- `npm run build:hardhat` or `hardhat compile` - Build using Hardhat toolchain
- `npm run clean` - Clean all build artifacts (Forge, Hardhat, TypeScript)

### Testing Commands  
- `npm run test` or `forge test` - Run tests using Foundry's testing framework
- `npm run test:hardhat` - Run tests using Hardhat/Mocha
- `forge test --gas-report` or `npm run gas-report` - Generate gas usage reports
- `forge coverage` or `npm run coverage` - Generate test coverage reports

### TypeScript Support
- `npm run typecheck` - Type check TypeScript files without compilation
- `npm run compile` - Compile contracts and generate TypeChain types

### Deployment Commands (via Makefile in protocol/)
- `make deploy CHAIN=Bsc` - Deploy contracts (auto-detects relay vs gateway)
- `make upgrade CHAIN=Bsc CONTRACT=Gateway` - Upgrade specific contract
- `make deploy-dry CHAIN=Bsc` - Dry-run deployment
- `make gen-verify CONTRACT=Gateway` - Generate verification files

### Configuration Commands (Hardhat tasks in protocol/)
- `npx hardhat setup:init --network Mapo` - Full initialization (dry-run by default)
- `npx hardhat setup:addChain --chain Eth --network Mapo` - Add a new chain (dry-run by default)
- All batch tasks support `--dryrun false` to execute changes

### Code Quality
- `forge fmt` or `npm run format` - Format Solidity code

### Common Library Commands

For `common/` directory:
- `npm run build` or `forge build` - Build common contracts
- `npm run build:hardhat` - Build using Hardhat and generate TypeChain types
- `npm run test` or `forge test` - Run tests for common contracts
- `forge fmt` or `npm run format` - Format Solidity code
- `npm run clean` - Clean all build artifacts
- `npm run prepublishOnly` - Prepare for npm publish (clean, build, typecheck)
- `npm publish` - Publish to npm registry as @mapprotocol/common-contracts

### Common Deployment Commands (via Makefile in common/)
- `make deploy-authority CHAIN=Bsc` - Deploy AuthorityManager (direct)
- `make deploy-authority-factory CHAIN=Bsc SALT=mapo_authority` - Deploy via CREATE2 factory
- `make deploy-authority CHAIN=Mapo` - Deploy with blockscout verification
- Tron deployment: `npx hardhat auth:deploy --network Tron`

### Common Authority Management (Hardhat tasks in common/)
- `npx hardhat auth:deploy --network Tron` - Deploy AuthorityManager (Tron only)
- `npx hardhat auth:grant --account <addr> --role admin --network <chain>` - Grant role
- `npx hardhat auth:revoke --account <addr> --role admin --network <chain>` - Revoke role
- `npx hardhat auth:getMember --role admin --network <chain>` - List role members
- `npx hardhat auth:setTarget --target <addr> --funcs <selectors> --role admin --network <chain>` - Set function permissions
- `npx hardhat auth:setAuth --target <addr> --addr <new_auth> --network <chain>` - Update authority
- `npx hardhat auth:closeTarget --target <addr> --close true --network <chain>` - Close/open target

## Architecture Overview

This project uses a hybrid Foundry + Hardhat setup for maximum compatibility:

### Dual Toolchain Support
- **Foundry (Primary)**: Fast Rust-based toolchain for Solidity development
  - Testing with `forge-std` 
  - Gas-optimized builds
  - Built-in fuzz testing support
- **Hardhat (Secondary)**: Node.js toolchain for ecosystem compatibility
  - TypeChain integration for type-safe contract interactions
  - Extensive plugin ecosystem
  - Hardhat Network for local development

### Configuration Files
- `foundry.toml` - Foundry configuration (Solidity 0.8.20, optimizer enabled)
- `hardhat.config.ts` - Hardhat configuration with Foundry compatibility
- `tsconfig.json` - TypeScript configuration for scripts and tests

### Smart Contract Organization
- `contracts/` - Contract source files (unified for both Foundry and Hardhat)
- `test/` - Test files (`.t.sol` for Foundry tests)
- `script/` - Deployment scripts for Foundry (`.s.sol`)
- `scripts/` - TypeScript deployment scripts for Hardhat

### Dependencies
- OpenZeppelin contracts (both standard and upgradeable versions)
- forge-std for Foundry testing utilities
- Full TypeScript toolchain with ethers.js v6

## Testing Strategy

The project supports both Foundry and Hardhat testing patterns:
- Foundry tests inherit from `forge-std/Test.sol`
- Support for fuzz testing with `testFuzz_` prefix
- Unit tests use `test_` prefix
- Hardhat tests use Mocha/Chai with TypeScript support

## Development Workflow

1. Smart contracts are developed in `contracts/` directory (unified for both toolchains)
2. Tests should be written for both toolchains when applicable
3. Use `forge fmt` to maintain consistent code formatting
4. Run both build systems to ensure compatibility: `npm run build && npm run build:hardhat`
5. Verify tests pass in both environments: `npm run test && npm run test:hardhat`

## File Organization Notes

- Both Foundry and Hardhat have been configured to use the unified `contracts/` directory
- This eliminates the need to maintain contracts in separate directories
- All import paths in tests and scripts reference `../contracts/` for consistency

## NPM Package Integration

To use npm packages in Forge, configure remappings in `foundry.toml`:

```toml
remappings = [
    '@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/',
    '@openzeppelin/contracts-upgradeable/=node_modules/@openzeppelin/contracts-upgradeable/',
    '@mapprotocol/atlas-contracts/=node_modules/@mapprotocol/atlas-contracts/',
    "forge-std/=lib/forge-std/src/"
]
```

This allows importing npm packages in Solidity files:
```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@mapprotocol/atlas-contracts/contracts/interface/ILightNode.sol";
```

When adding new npm packages:
1. Install the package: `npm install <package-name>`
2. Add corresponding remapping in `foundry.toml`
3. Forge will automatically resolve imports from `node_modules/`

## Common Library Usage

The `common/` directory is published as an npm package `@mapprotocol/common-contracts`:

### Using in Other Projects

```bash
npm install @mapprotocol/common-contracts
```

### Import in Solidity
```solidity
import "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

abstract contract MyContract is BaseImplementation {
    function initialize(address _admin) public initializer {
        __BaseImplementation_init(_admin);
        // Your initialization logic
    }
}
```

### Key Features
- **BaseImplementation**: Abstract base contract with UUPS upgradeable, pausable, and access control
- **AuthorityManager**: Flexible authority and role management
- **TypeScript Support**: Full TypeChain generated types for type-safe development
- **Dual Toolchain**: Works with both Foundry and Hardhat
- **Shared Utils**: TypeScript utilities for deployment, Tron interaction, and address encoding

### Import Utils in TypeScript
```typescript
import { getDeploymentByKey, saveDeployment } from "@mapprotocol/common-contracts/utils/deployRecord";
import { TronClient, tronToHex, tronFromHex } from "@mapprotocol/common-contracts/utils/tronHelper";
import { addressToHex, isTronAddress } from "@mapprotocol/common-contracts/utils/addressCodec";
```

### Forge Script Base (published in npm)
```solidity
import {BaseScript} from "@mapprotocol/common-contracts/script/base/Base.s.sol";

contract MyDeploy is BaseScript {
    function run() public broadcast {
        // deployByFactory(salt, creationCode, args) — CREATE2 deterministic deploy
        // upgradeProxy(proxy, newImpl) — UUPS upgrade
        // deployAndUpgrade(proxy, creationCode) — deploy + upgrade in one step
    }
}
```

<!-- GSD:project-start source:PROJECT.md -->
## Project

**MAP Protocol v2 Contracts**

MAP Protocol v2.0 cross-chain bridge smart contracts — a decentralized cross-chain asset transfer system based on TSS (Threshold Signature Scheme). The contracts are deployed across the MAPO relay chain and multiple external chains (EVM, Bitcoin, Tron, Solana), enabling secure cross-chain operations through 2/3 threshold signatures without centralized custody.

This repository contains the on-chain components: relay chain core contracts (protocol/), TSS maintainer management (maintainer/), shared base library (common/), and external chain gateway contracts.

**Core Value:** Secure, decentralized cross-chain asset custody and transfer through TSS threshold signatures — no single entity can control or steal cross-chain assets.

### Constraints

- **Compatibility**: Contracts already deployed in production — changes must be upgrade-safe (UUPS proxy pattern)
- **Multi-chain**: Any contract change must consider deployment across 14+ chains with different gas models
- **Security**: Cross-chain bridge managing real assets — security is non-negotiable, every change needs audit consideration
- **Solidity version**: 0.8.25 with optimizer enabled (200 runs)
- **Dependencies**: OpenZeppelin v5.4.0 (contracts + upgradeable), @mapprotocol/atlas-contracts for interfaces
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages & Versions
- Solidity 0.8.25 - Smart contracts in `protocol/` and `maintainer/` modules
- Solidity 0.8.24 - Smart contracts in `common/` module
- Solidity ^0.8.20 - Base contracts and interfaces (pragma range)
- TypeScript ^5.0 - Deployment scripts, Hardhat tasks, configuration
- JavaScript (CommonJS) - TronWeb integration (`common/utils/tronHelper.ts`)
## Runtime
- Node.js >=18.0.0 (inferred from `@types/node` versions)
- Foundry/Forge (Rust-based Solidity toolchain, primary)
- npm (each module has its own `package.json`)
- Lockfiles: per-module `node_modules/` directories
## Frameworks & Tooling
- Foundry/Forge - Primary build, test, deploy, and formatting tool
- Hardhat ^2.19.0 - Secondary toolchain for TypeScript integration and tasks
- forge-std (Foundry) - Primary Solidity test framework (`lib/forge-std/`)
- Hardhat Toolbox ^4.0.0 - Includes Mocha, Chai, ethers.js for JS/TS tests
- Chai ^4.2.0 - Assertion library
- hardhat-gas-reporter ^1.0.8 - Gas usage reporting
- solidity-coverage ^0.8.x - Test coverage
- TypeChain ^8.3.0 - Generate TypeScript types from contract ABIs
- @typechain/ethers-v6 ^0.5.0 - ethers.js v6 bindings
- @typechain/hardhat ^9.0.0 - Hardhat integration
- ts-node ^10.0.0 - TypeScript execution
- dotenv ^16.0.3 - Environment variable loading
- `forge fmt` - Solidity formatter
- @nomicfoundation/hardhat-verify ^2.0.0 - Etherscan/Blockscout verification via Hardhat
- `forge verify-contract` - Foundry native verification
## Dependencies
### Production
- `@openzeppelin/contracts` 5.4.0 - Standard contract library (ERC20, ECDSA, ERC1967, AccessManager)
- `@openzeppelin/contracts-upgradeable` 5.4.0 - Upgradeable patterns (UUPSUpgradeable, PausableUpgradeable, AccessManagedUpgradeable)
- `@mapprotocol/common-contracts` ^0.4.1 - Shared base contracts + utils + forge script base (published npm package)
- forge-std - Testing utilities, Script base, console logging (`lib/forge-std/`)
### Development
- `@nomicfoundation/hardhat-toolbox` ^4.0.0
- `@nomicfoundation/hardhat-ethers` ^3.0.0
- `@nomicfoundation/hardhat-chai-matchers` ^2.0.0
- `@nomicfoundation/hardhat-network-helpers` ^1.0.0
- `@nomicfoundation/hardhat-foundry` ^1.1.1
- `@nomicfoundation/hardhat-verify` ^2.0.0
- ethers ^6.4.0 - Ethereum interaction library
- tronweb ^5.3.0 - Tron blockchain interaction (protocol module only)
## Build & Deploy Pipeline
# Foundry deployment with broadcast
# With Etherscan verification (EVM chains)
# MAPO chain verification (Blockscout - separate step)
- `hardhat run scripts/deploy.ts` - Hardhat deployment
- Custom Hardhat tasks in `protocol/tasks/subs/` for contract configuration:
- `hardhat upgrade --contract <name>` - UUPS proxy upgrade task
## Configuration
- `.env.example` files present in all three modules
- `PRIVATE_KEY` - Mainnet deployer key
- `TESTNET_PRIVATE_KEY` - Testnet deployer key
- `TRON_PRIVATE_KEY` - Tron network deployment
- `TRON_RPC_URL` - Tron RPC endpoint
- `ETHERSCAN_API_KEY` - Contract verification
- `GATEWAY_SALT` - CREATE2 deployment salt
- `NETWORK_ENV` - **Required.** Deployment environment: `test`, `prod`, or `main`. No default — must be set in .env
  - Determines deploy.json key: `NETWORK_ENV=prod` + network `Bsc` → `prod.Bsc`
  - Determines config directory: `test` → `configs/testnet/`, `prod` → `configs/prod/`, `main` → `configs/mainnet/`
- `protocol/deployments/deploy.json` - Deployed contract addresses (nested: `{ env: { chain: { key: addr } } }`)
- `protocol/configs/prod/` - Production chain and token configurations
- `protocol/configs/mainnet/` - Mainnet configurations
- `protocol/configs/testnet/` - Testnet configurations
## Platform Requirements
- Foundry toolchain installed (forge, cast, anvil)
- Node.js >= 18
- npm for dependency management
- EVM-compatible blockchains (Solidity 0.8.25, EVM version: london)
- UUPS proxy pattern for upgradeable contracts
- CREATE2 factory at `0x6258e4d2950757A749a4d4683A7342261ce12471` for deterministic deployments
## NPM Publishing
- Registry: https://registry.npmjs.org/
- Access: public
- Published files: `contracts/**/*.sol`, `artifacts/`, `typechain-types/`
- Prepublish: `clean -> build:hardhat -> typecheck`
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- Use PascalCase for contract names: `VaultManager`, `BaseGateway`, `TSSManager`
- Use PascalCase for interface names, prefixed with `I`: `IVaultManager`, `IGateway`, `ITSSManager`
- Base/abstract contracts use `Base` prefix: `BaseImplementation`, `BaseGateway`, `BaseScript`
- Contract files use PascalCase matching contract name: `VaultManager.sol`, `Gateway.sol`
- Interface files use PascalCase with `I` prefix: `IVaultManager.sol`, `IGateWay.sol`
- Library files use PascalCase: `Utils.sol`, `Types.sol`, `Errors.sol`, `Constants.sol`
- Script files use PascalCase: `Base.s.sol`, `DeployAndSetUp.s.sol`
- Use camelCase for all functions: `bridgeOut()`, `executeTxIn()`, `setVaultManager()`
- Internal/private functions use `_` prefix: `_bridgeOut()`, `_checkAccess()`, `_getActiveVault()`
- Getter functions use `get` prefix: `getEpochInfo()`, `getSlashPoint()`, `getMembers()`
- Setter functions use `set` prefix: `setRegistry()`, `setWtoken()`, `setVaultManager()`
- Boolean getters use `is`/`check` prefix: `isOrderExecuted()`, `isMintable()`, `checkVault()`
- Initializer functions are always named `initialize(address _defaultAdmin)`
- Use camelCase for state variables: `currentEpoch`, `activeTssAddress`, `selfChainId`
- Use `_` prefix for function parameters: `_defaultAdmin`, `_tss`, `_token`
- Use camelCase for local variables: `txItem`, `bridgeItem`, `gasInfo`
- Constants use UPPER_SNAKE_CASE: `TSS_MAX_NUMBER`, `MAX_RATE_UNIT`, `ORDER_NOT_EXIST`
- Constants as `bytes32` hashes use UPPER_SNAKE_CASE: `REWARD_PER_BLOCK`, `BLOCKS_PER_EPOCH`
- Use PascalCase: `TxItem`, `BridgeItem`, `GasInfo`, `TSSInfo`, `NetworkFee`
- Use PascalCase for enum name: `TxType`, `ChainType`, `TSSStatus`, `MaintainerStatus`
- Use UPPER_SNAKE_CASE for enum values: `KEYGEN_PENDING`, `KEYGEN_COMPLETED`, `ACTIVE`
- Use PascalCase: `BridgeOut`, `BridgeIn`, `UpdateTSS`, `SetRegistry`
- Match the action they represent: `Set(...)`, `Rotate(...)`, `Retire(...)`
- Use snake_case for custom errors: `order_executed()`, `invalid_signature()`, `no_access()`
- Errors with parameters also use snake_case: `invalid_token_balance(address, uint256)`
- Errors are defined at the contract level, not in a central location (except `Errs` library in protocol)
## Code Style
- Only `common/` module has explicit `forge fmt` config in `foundry.toml`:
- `protocol/` and `maintainer/` rely on default `forge fmt` settings
- Use `forge fmt` to format all Solidity code before committing
- No `.solhint`, `.eslintrc`, or `.prettierrc` configs detected
- Rely on compiler warnings and `forge fmt` for code quality
- Implementation contracts use exact version: `pragma solidity 0.8.25;`
- Interfaces and libraries use caret version: `pragma solidity ^0.8.20;` or `pragma solidity ^0.8.0;`
- Common contracts use `^0.8.20`
- All files use `// SPDX-License-Identifier: MIT`
## Import Organization
- Use named imports with curly braces: `import {TypeA, TypeB} from "./path";`
- Never use wildcard imports
- Group related imports but no strict empty-line separation between groups
- `@openzeppelin/contracts/` -> `node_modules/@openzeppelin/contracts/`
- `@openzeppelin/contracts-upgradeable/` -> `node_modules/@openzeppelin/contracts-upgradeable/`
- `@mapprotocol/common-contracts/` -> `node_modules/@mapprotocol/common-contracts/`
- `forge-std/` -> `../lib/forge-std/src/`
## Error Handling
- Define custom errors at the contract level:
- Use `revert` with custom errors for specific failure conditions:
- Use bare `require` without error messages:
- Never use require with string messages in this codebase
- `protocol/contracts/libs/Errors.sol` defines `library Errs` with shared errors
- Referenced as `Errs.order_executed()`, `Errs.invalid_vault()`, etc.
- Gateway.sol and other contracts also define their own errors locally
- Used for external calls that may fail gracefully:
- Token transfers use low-level `.call()` with selector bytes instead of SafeERC20:
- Balance-before/after pattern verifies transfer success (see `BaseGateway._transferFromToken`)
## Access Control Patterns
- All implementation contracts inherit `BaseImplementation` from `@mapprotocol/common-contracts`
- `BaseImplementation` extends: `UUPSUpgradeable`, `PausableUpgradeable`, `AccessManagedUpgradeable`
- Used for admin/role-gated functions:
- `onlyMaintainer` in `TSSManager.sol` for maintainer-only functions
- `onlyVm` in `Maintainers.sol` for VM-level calls (`msg.sender == address(0)`)
- `onlyManager` in `VaultToken.sol` for vault manager calls
- `Relay.sol` uses `_checkAccess(ContractType)` to verify caller is a registered contract:
- `whenNotPaused` modifier on user-facing functions: `bridgeOut`, `bridgeIn`, `deposit`
- Toggle via `trigger()` function (restricted): pauses if running, unpauses if paused
- `nonReentrant` modifier from `ReentrancyGuardUpgradeable` on entry points
## Events & Logging
- Emit events after state changes, at the end of the function or after the relevant state mutation
- Events include all relevant data for off-chain indexing
- Use `indexed` on key fields (orderId, chainAndGasLimit) for efficient filtering:
- Every setter function emits a corresponding event:
## Upgrade Pattern
- All contracts use UUPS upgradeable proxy via `BaseImplementation`
- Constructor disables initializers: `constructor() { _disableInitializers(); }`
- Initialize via `initialize(address _defaultAdmin)` with `initializer` modifier
- Custom `ERC1967Proxy.sol` in each module (not OpenZeppelin's default)
- `_authorizeUpgrade` is `restricted` (admin-only)
- Use deterministic deployment via factory contract at `0x6258e4d2950757A749a4d4683A7342261ce12471`
- Deployment scripts extend `BaseScript` with `broadcast()` modifier
- Config stored in `deployments/deploy.json`
## Gas Optimization Patterns
- Used consistently in `TSSManager.sol`, `Maintainers.sol`
- Some loops in `ProtocolFee.sol`, `BaseGateway.sol` use standard `i++` (inconsistent)
- Use smaller uint types for storage: `uint64`, `uint128` for block numbers, gas values
- Example: `OrderInfo` struct packs `bool signed`, `uint64 height`, `address gasToken`, `uint128 estimateGas`
- Use `constant` for compile-time values: `uint256 constant TOKEN_BRIDGEABLE = 0x01;`
- Use `immutable` for deploy-time values: `uint256 public immutable selfChainId = block.chainid;`
- Chain IDs and gas limits packed into single `uint256`:
- Token capabilities stored as bit flags: `TOKEN_BRIDGEABLE = 0x01`, `TOKEN_MINTABLE = 0x02`, `TOKEN_BURNFROM = 0x04`
## Documentation
- Used selectively, not universally
- Interface functions in `IMaintainers.sol` have full `@notice`, `@dev`, `@param` documentation
- `IVaultManager.sol` has `@notice`, `@dev`, `@return` on complex functions
- Implementation contracts have minimal NatSpec (mostly inline comments)
- `VaultManager.sol` has a comprehensive contract-level `@title`/`@dev` block
- Used for explaining complex logic, especially bitwise operations
- Comments use `//` style, not `/* */`
- Some TODO/FIXME comments remain: `// todo: check status`, `// todo: save in/out tx hash?`
- Add comments for bitwise operations and encoding schemes
- Add comments for non-obvious business logic decisions
- Add NatSpec on public interface functions
- No requirement for comments on straightforward getter/setter functions
## Module Organization
- Own `package.json`, `foundry.toml`, `hardhat.config.ts`, `tsconfig.json`
- Own `contracts/` directory with flat structure
- Subdirectories: `interfaces/`, `libs/`, `base/`, `len/` (protocol only)
- Deployment scripts in `scripts/foundry/` (Foundry) and `scripts/` (Hardhat)
- `common/` published as `@mapprotocol/common-contracts` npm package
- Provides `BaseImplementation` and `AuthorityManager`
- Consumed by both `protocol/` and `maintainer/` via npm dependency
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- The MAPO relay chain hosts all core protocol logic (Relay, VaultManager, Registry, GasService)
- External EVM chains run lightweight Gateway contracts that only handle lock/unlock and signature verification
- Non-EVM chains (Bitcoin, Tron, etc.) are supported via TSS (Threshold Signature Scheme) vault addresses
- All contracts use UUPS upgradeable proxy pattern via OpenZeppelin
- Access control uses OpenZeppelin's `AccessManager` (not role-based `AccessControl`)
## Layers
- Purpose: Base abstractions shared across all modules
- Location: `common/contracts/`
- Contains:
- Depends on: OpenZeppelin contracts
- Used by: Both `protocol/` and `maintainer/` modules (via npm package `@mapprotocol/common-contracts`)
- Purpose: Core cross-chain bridge logic deployed on MAPO relay chain
- Location: `protocol/contracts/`
- Contains: Relay, VaultManager, Registry, GasService, ProtocolFee, VaultToken, Gateway
- Depends on: `common/` (BaseImplementation), OpenZeppelin
- Used by: Off-chain relayers, TSS maintainers, end users
- Purpose: Decentralized maintainer election, TSS key management, cross-chain transaction voting
- Location: `maintainer/contracts/`
- Contains: Maintainers, TSSManager, Parameters
- Depends on: `common/` (BaseImplementation), OpenZeppelin
- Used by: Validators, maintainer nodes
- Purpose: Read-only view contracts, cross-protocol connectors
- Location: `protocol/contracts/len/`
- Contains: ViewController, FusionReceiver, FusionQuoter, Configuration, FlashSwapManager
- Depends on: Protocol layer interfaces
- Used by: Front-end applications, external integrators
## Contract Relationships
### Relay Chain Contracts (MAPO)
```
```
### External Chain Contracts (BSC, ETH, Base, Arb, Tron, etc.)
```
```
### Registry as Service Locator
```solidity
```
## Data Flow
### Cross-Chain Transfer (Chain A -> Chain B via Relay):
### Same-Chain Transfer (Relay Chain -> Relay Chain):
- Calls `_bridgeIn()` internally (line 456)
- Transfers tokens directly to recipient
- Calls `IReceiver.onReceived()` if recipient is a contract with payload
### Deposit Flow (Any Chain -> Vault Token):
### FusionReceiver Flow (Cross-Protocol Bridge):
- **BUTTER (MOS)**: Legacy MAP Omnichain Service
- **TSS Gateway**: New TSS-based bridge
- MOS -> FusionReceiver -> TSS Gateway (`_forwardToGateway`)
- TSS Gateway -> FusionReceiver -> MOS (`_forwardToMos`)
- Failed forwards are stored and can be retried
## Upgrade Patterns
- All contracts inherit `BaseImplementation` which includes `UUPSUpgradeable`
- Proxy: `ERC1967Proxy` at `protocol/contracts/ERC1967Proxy.sol` and `maintainer/contracts/ERC1967Proxy.sol`
- `_authorizeUpgrade()` is restricted via AccessManaged
- Constructor calls `_disableInitializers()` to prevent implementation initialization
- `AuthorityManager` at `common/contracts/AuthorityManager.sol` extends `AccessManager`
- Adds enumerable role member tracking
- All restricted functions use `restricted` modifier (from `AccessManagedUpgradeable`)
- One `AuthorityManager` deployed per chain to control all contracts on that chain
- All contracts use `initialize()` pattern with `initializer` modifier
- Base initialization via `__BaseImplementation_init(address _defaultAdmin)` which sets up Pausable, AccessManaged, and UUPSUpgradeable
- All contracts inherit `PausableUpgradeable`
- Toggle via `trigger()` function (restricted) which flips pause state
## Key Abstractions
- Purpose: Represents a cross-chain transaction on the relay chain with normalized (relay chain) token and amount
- Defined at: `protocol/contracts/libs/Types.sol` line 31
- Contains: orderId, vaultKey, chain, chainType, token (relay chain address), amount (relay chain decimals)
- Purpose: Represents bridge data with source/destination chain token addresses and amounts
- Defined at: `protocol/contracts/libs/Types.sol` line 47
- Contains: chainAndGasLimit (packed uint256), vault, txType, sequence, token (bytes), amount, from, to, payload
- `chainAndGasLimit` packs multiple values into a single uint256: `fromChain (8 bytes) | toChain (8 bytes) | txRate (8 bytes) | txSize (8 bytes)`
- Parsed via bit shifting in `_getFromAndToChain()` and `_getChainAndGasLimit()`
- `bytes32` derived from TSS public key via `Utils.getVaultKey()`
- Used as identifier for vault state tracking in VaultManager
- `TOKEN_BRIDGEABLE = 0x01` -- Can be bridged
- `TOKEN_MINTABLE = 0x02` -- Contract can mint/burn
- `TOKEN_BURNFROM = 0x04` -- Supports burnFrom pattern
## Entry Points
- Location: `protocol/contracts/base/BaseGateway.sol` line 155
- Triggers: User initiates cross-chain transfer
- Responsibilities: Receive tokens, validate, emit BridgeOut event
- Location: `protocol/contracts/Gateway.sol` line 66
- Triggers: Off-chain relayer delivers tokens with TSS signature
- Responsibilities: Verify signature, mint/transfer tokens to recipient
- Location: `protocol/contracts/Relay.sol` line 287
- Triggers: TSSManager after maintainer consensus
- Responsibilities: Process incoming cross-chain transfer, route to destination
- Location: `protocol/contracts/Relay.sol` line 227
- Triggers: TSSManager after delivery confirmation
- Responsibilities: Settle gas fees, update vault balances, clean up order
- Location: `protocol/contracts/Relay.sol` lines 163, 169
- Triggers: TSSManager during vault key rotation
- Responsibilities: Coordinate vault migration across chains
## Error Handling
- Central error library: `protocol/contracts/libs/Errors.sol` (Errs library)
- Per-contract custom errors for contract-specific cases (e.g., Gateway: `order_executed`, `invalid_signature`)
- `require()` with no message for simple checks (e.g., `require(_wToken != ZERO_ADDRESS)`)
- Try/catch for external calls that should not revert the entire transaction (e.g., affiliate fee collection, token swap, `onReceived` callback)
- Failed bridge deliveries stored in `orderExecuted` mapping with hash for retry
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
