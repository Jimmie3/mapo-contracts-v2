# CLAUDE.md - Maintainer Module

This file provides guidance for the maintainer module of MAP Protocol contracts.

## Module Overview

The maintainer module implements a decentralized TSS (Threshold Signature Scheme) maintainer system. Validators can register maintainers who participate in TSS key generation and cross-chain asset management.

## Core Contracts

### Maintainers.sol
Manages maintainer registration, activation, and election lifecycle.

**Key Functions:**
- `register()` - Validator registers a maintainer (UNKNOWN -> REGISTERED)
- `activate()` - Maintainer activates to participate in election (REGISTERED -> STANDBY)
- `revoke()` - Maintainer revokes candidacy (STANDBY/READY/ACTIVE -> REGISTERED)
- `update()` - Validator updates maintainer info (REGISTERED -> STANDBY)
- `deregister()` - Validator removes maintainer registration
- `orchestrate()` - Orchestrates election and migration process
- `distributeReward()` - Distributes epoch rewards to maintainers

**Maintainer Status Flow:**
```
UNKNOWN -> REGISTERED -> STANDBY -> READY -> ACTIVE
                ^                              |
                |______________________________|
                         (revoke)
```

### TSSManager.sol
Manages TSS key generation, rotation, and cross-chain operations.

**Key Responsibilities:**
- TSS key generation consensus
- Epoch rotation and migration
- Slash point management
- Cross-chain transaction voting (TxIn/TxOut)

**TSS Status:**
- `UNKNOWN` - Initial state
- `KEYGEN_CONSENSUS` - Waiting for key generation consensus
- `KEYGEN_COMPLETED` - Key generation completed
- `KEYGEN_FAILED` - Key generation failed
- `ACTIVE` - Currently active TSS
- `MIGRATED` - Migration completed

### Parameters.sol
Simple key-value store for system parameters.

**Key Parameters:**
- `REWARD_PER_BLOCK` - Reward amount per block
- `BLOCKS_PER_EPOCH` - Number of blocks per epoch
- `MAX_BLOCKS_FOR_UPDATE_TSS` - Max blocks allowed for TSS update
- `MAX_SLASH_POINT_FOR_ELECT` - Max slash points to be eligible for election
- `JAIL_BLOCK` - Number of blocks for jail duration

## Interfaces

| Interface | Description |
|-----------|-------------|
| `IMaintainers.sol` | Maintainer management interface |
| `ITSSManager.sol` | TSS management interface |
| `IParameters.sol` | Parameters storage interface |
| `IAccounts.sol` | MAP chain accounts interface |
| `IValidators.sol` | MAP chain validators interface |
| `IElection.sol` | MAP chain election interface |
| `IRelay.sol` | Cross-chain relay interface |

## Development Commands

```bash
# Build
npm run build          # or forge build

# Test
npm run test           # or forge test
forge test -vvv        # verbose test output

# Format
forge fmt

# Gas report
npm run gas-report
```

## Architecture Notes

### Dual Role System
- **Validator**: Registers and manages maintainer info (calls register/update/deregister)
- **Maintainer**: Controls participation status (calls activate/revoke/heartbeat)

### Epoch Lifecycle
1. **Election**: Maintainers in STANDBY/READY/ACTIVE with low slash points are elected
2. **Keygen**: Elected maintainers generate new TSS key
3. **Rotation**: New TSS becomes active, old TSS starts migration
4. **Migration**: Assets transferred from old TSS to new TSS
5. **Retire**: Old TSS retired, new epoch fully active

### Key Verification
- `secp256k1 pubkey` must derive to maintainer address via `keccak256(pubkey)`
- `ed25519 pubkey` used for TSS protocol operations

## Constants

```solidity
TSS_MAX_NUMBER = 30    // Maximum maintainers in TSS
TSS_MIN_NUMBER = 3     // Minimum maintainers required
```

## Dependencies

- `@openzeppelin/contracts` - Standard utilities
- `@openzeppelin/contracts-upgradeable` - Upgradeable patterns
- `@mapprotocol/common-contracts` - BaseImplementation base contract