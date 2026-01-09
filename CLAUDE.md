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

### Deployment Commands
- `npm run deploy` - Deploy using Forge (requires RPC_URL and PRIVATE_KEY env vars)
- `npm run deploy:hardhat` - Deploy using Hardhat scripts
- `forge script script/Deploy.s.sol --rpc-url <url> --private-key <key> --broadcast` - Direct Forge deployment

### Code Quality
- `forge fmt` or `npm run format` - Format Solidity code

### Common Library Commands

For `common/` directory:
- `npm run build` or `forge build` - Build common contracts
- `npm run build:hardhat` - Build using Hardhat and generate TypeChain types
- `npm run test` or `forge test` - Run tests for common contracts
- `npm run test:hardhat` - Run Hardhat tests
- `forge fmt` or `npm run format` - Format Solidity code
- `npm run clean` - Clean all build artifacts
- `npm run compile` - Compile and generate TypeScript types
- `npm run prepublishOnly` - Prepare for npm publish (clean, build, typecheck)
- `npm publish` - Publish to npm registry as @mapprotocol/common-contracts

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