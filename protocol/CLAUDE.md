# CLAUDE.md - Protocol Contracts

This file provides guidance to Claude Code when working with the MAP Protocol core contracts.

## Overview

The protocol directory contains the core smart contracts for MAP Protocol's cross-chain bridge system. These contracts handle asset transfers, vault management, and cross-chain communication.

## Architecture

### Core Contracts

#### 1. **Relay.sol**
- Central contract for cross-chain bridge operations
- Handles incoming (`executeTxIn`) and outgoing (`executeTxOut`) transfers
- Manages order execution and tracking
- Integrates with VaultManager for vault selection
- Processes refunds when transfers fail
- Key responsibilities:
  - Token minting/burning for cross-chain transfers
  - Fee collection (affiliate, security, vault fees)
  - Transaction validation and signature verification
  - Emitting bridge events for off-chain relayers

#### 2. **VaultManager.sol**
- Manages vault lifecycle and operations
- Handles vault rotation and migration
- Tracks token balances across chains
- Key features:
  - **Vault Selection**: Contract chains use active vault; non-contract chains select based on allowances
  - **Migration**: Contract chains update mappings only; non-contract chains transfer actual assets
  - **Balance Tracking**: Per-chain, per-token balance management with pending amounts
  - **Refund Logic**: Handles refunds with gas fee considerations

#### 3. **Gateway.sol**
- Entry point for users to initiate bridge operations
- Handles deposits and bridge-out requests
- Manages token transfers and validation

#### 4. **Periphery.sol**
- Central registry for protocol components
- Provides unified access to:
  - Relay contract (type 0)
  - GasService (type 1)
  - VaultManager (type 2)
  - TokenRegistry (type 3)
  - TSSManager (type 4+)
- Helper functions for chain info and gas calculations

### Supporting Contracts

- **BaseGateway.sol**: Base implementation for gateway contracts
- **RelayGateway.sol**: Specialized gateway for relay operations
- **Interfaces**: Define contract interactions and standards
- **Libraries**:
  - `Types.sol`: Core data structures (TxItem, BridgeItem, GasInfo, etc.)
  - `Utils.sol`: Utility functions
  - `Errors.sol`: Custom error definitions

## Key Concepts

### Transaction Types
- **TRANSFER**: Regular cross-chain transfer
- **DEPOSIT**: Deposit to vault token
- **MIGRATE**: Vault migration operation
- **REFUND**: Return funds to sender

### Chain Types
- **CONTRACT**: Smart contract chains (EVM-compatible)
- **UTXO**: Bitcoin-like UTXO chains
- **Other**: Custom chain types

### Fee Structure
1. **Affiliate Fees**: Optional fees for integrators
2. **Security Fees**: Protocol security fund
3. **Vault Fees**: Vault operation costs
4. **Gas Fees**: Network transaction costs

### Vault Management Principles

1. **Active vs Retiring Vaults**: System maintains one active and optionally one retiring vault
2. **Migration Process**:
   - Contract chains: Update references only
   - Non-contract chains: Physical asset migration with gas calculations
3. **Refund Conditions**:
   - Vault is retired (not active or retiring)
   - Insufficient funds after fees and swaps
   - Amount below minimum thresholds

## Development Workflow

### Building
```bash
npm run build        # Build with Foundry
forge build          # Direct Foundry build
```

### Testing
```bash
npm run test         # Run Foundry tests
forge test           # Direct Foundry test
forge test --gas-report  # With gas reporting
```

### Deployment
```bash
forge script script/Deploy.s.sol --rpc-url <url> --private-key <key> --broadcast
```

## Important Notes

### Access Control
- Most state-changing functions in VaultManager are restricted to Relay contract
- Administrative functions use role-based access control
- Critical operations check access through Periphery contract

### Gas Management
- All cross-chain operations estimate and reserve gas
- Gas fees are calculated in relay chain tokens
- Refunds account for gas costs to prevent dust transactions

### State Management
- Order execution tracked via orderExecuted/outOrderExecuted mappings
- Chain sequences track transaction ordering
- Last scan blocks prevent replay attacks

## Testing Considerations

When testing protocol contracts:
1. Mock Periphery and Registry contracts for unit tests
2. Test vault rotation scenarios thoroughly
3. Verify refund logic under various conditions
4. Test gas estimation and fee calculations
5. Validate signature verification in relaySigned

## Security Considerations

1. **Signature Verification**: All TSS operations verify signatures
2. **Access Control**: Strict role-based permissions
3. **Reentrancy Protection**: State updates before external calls
4. **Amount Validation**: Check for underflows in fee calculations
5. **Vault State**: Ensure consistent vault state during migrations