# @mapprotocol/common-contracts

Common smart contracts library for MAP Protocol.

## Installation

```bash
npm install @mapprotocol/common-contracts
```

or

```bash
yarn add @mapprotocol/common-contracts
```

## Usage

### Solidity Contracts

Import contracts in your Solidity files:

```solidity
import "@mapprotocol/common-contracts/contracts/base/BaseImplemention.sol";
import "@mapprotocol/common-contracts/contracts/AuthorityManager.sol";
```

### TypeScript/JavaScript

Use TypeChain generated types for type-safe contract interactions:

```typescript
import { BaseImplement__factory } from "@mapprotocol/common-contracts";
import { ethers } from "ethers";

// Deploy or connect to contract
const signer = await ethers.getSigner();
const baseContract = await BaseImplement__factory.deploy(signer);

// Or connect to existing contract
const contractAddress = "0x...";
const contract = BaseImplement__factory.connect(contractAddress, signer);
```

## Contracts Overview

### Base Contracts
- `BaseImplemention.sol` - Base implementation with common functionality including pausable, reentrancy guard, and UUPS upgradeable patterns

### Authority Management
- `AuthorityManager.sol` - Authority and access control management

## Features

- **Upgradeable**: Contracts use UUPS (Universal Upgradeable Proxy Standard) pattern
- **Pausable**: Emergency pause functionality for critical operations
- **Reentrancy Protection**: Built-in reentrancy guards for secure operations
- **Access Control**: Flexible authority management system
- **TypeScript Support**: Full TypeChain generated types for type-safe development

## Development

This library uses a dual toolchain setup:

### Foundry
```bash
forge build          # Build contracts
forge test           # Run tests
forge fmt            # Format code
```

### Hardhat
```bash
npm run build:hardhat    # Build with Hardhat
npm run test:hardhat     # Run Hardhat tests
npm run compile          # Compile and generate types
```

### Other Commands
```bash
npm run clean            # Clean all artifacts
npm run typecheck        # Check TypeScript types
npm run gas-report       # Generate gas usage report
npm run coverage         # Generate test coverage
```

## Requirements

- Node.js >= 18.0.0
- Solidity 0.8.20

## Dependencies

- OpenZeppelin Contracts v5.0.0
- OpenZeppelin Contracts Upgradeable v5.0.0

## License

MIT

## Repository

[GitHub](https://github.com/mapprotocol/mapo-contracts-v2/tree/main/common)

## Issues

Please report issues at [GitHub Issues](https://github.com/mapprotocol/mapo-contracts-v2/issues)