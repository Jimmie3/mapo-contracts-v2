# MAP Protocol Contracts V2

Multi-chain smart contracts repository for MAP Protocol, featuring a modular architecture with shared libraries and chain-specific implementations.

## 📁 Project Structure

```
mapo-contracts-v2/
├── common/                  # Shared contracts library (npm: @mapprotocol/common-contracts)
│   ├── contracts/
│   │   ├── base/           # Abstract base contracts
│   │   └── periphery/      # Peripheral utilities
│   └── package.json        # Published as npm package
├── maintainer/             # Maintainer contracts with dual toolchain
│   ├── contracts/
│   │   ├── Maintainer.sol
│   │   ├── TSSManager.sol
│   │   └── interfaces/
│   └── package.json
├── protocol/               # Core protocol contracts
│   ├── contracts/
│   │   ├── Gateway.sol
│   │   ├── Relay.sol
│   │   ├── VaultManager.sol
│   │   └── interfaces/
│   └── package.json
├── mos-solana/            # Solana-specific implementations
└── affilate/              # Affiliate contracts

```

## 🚀 Quick Start

### Prerequisites

- Node.js >= 18.0.0
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- npm or yarn

### Installation

1. Clone the repository:
```bash
git clone https://github.com/mapprotocol/mapo-contracts-v2.git
cd mapo-contracts-v2
```

2. Install dependencies for each module:
```bash
# Common library
cd common && npm install

# Maintainer contracts
cd ../maintainer && npm install

# Protocol contracts
cd ../protocol && npm install
```

## 📦 Common Contracts Library

The `common/` directory is published as an npm package for reuse across projects.

### Using as NPM Package

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

- **BaseImplementation**: Abstract base contract with UUPS upgradeable pattern, pausable functionality, and access control
- **AuthorityManager**: Flexible authority and role management system
- **TypeScript Support**: Full TypeChain generated types for type-safe development
- **Dual Toolchain**: Works with both Foundry and Hardhat

## 🛠️ Development

### Build Commands

Each module supports both Foundry and Hardhat:

```bash
# Foundry build
npm run build

# Hardhat build with TypeChain
npm run build:hardhat

# Clean all artifacts
npm run clean
```

### Testing

```bash
# Foundry tests
npm run test

# Hardhat tests
npm run test:hardhat

# Gas reports
npm run gas-report

# Coverage
npm run coverage
```

### Code Quality

```bash
# Format Solidity code
npm run format

# Type checking
npm run typecheck
```

## 🏗️ Architecture

### Dual Toolchain Support

- **Foundry**: Fast Rust-based toolchain for Solidity development
  - Faster compilation and testing
  - Built-in fuzzing capabilities
  - Gas-optimized builds
  
- **Hardhat**: Node.js toolchain for ecosystem compatibility
  - TypeChain integration
  - Extensive plugin ecosystem
  - Better JavaScript/TypeScript integration

### Upgradeable Contracts

All core contracts use the UUPS (Universal Upgradeable Proxy Standard) pattern:
- Gas efficient proxy pattern
- Built-in upgrade authorization
- Compatible with OpenZeppelin's upgradeable contracts

## 📚 Module Overview

### Common (`common/`)
Shared base contracts and utilities used across all modules.

### Maintainer (`maintainer/`)
Contracts for managing network maintainers and TSS (Threshold Signature Scheme) operations.

### Protocol (`protocol/`)
Core protocol contracts including:
- Gateway: Cross-chain message gateway
- Relay: Message relay system
- VaultManager: Asset vault management
- TokenRegistry: Token registration and mapping

### MOS-Solana (`mos-solana/`)
Solana-specific Message Omnichain Service implementation.

## 🔗 Resources

- [Documentation](https://docs.mapprotocol.io)
- [MAP Protocol Website](https://mapprotocol.io)
- [GitHub Issues](https://github.com/mapprotocol/mapo-contracts-v2/issues)

## 📄 License

MIT

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request