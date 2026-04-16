# @mapprotocol/common-contracts

Shared smart contracts and TypeScript utilities for MAP Protocol's multi-chain infrastructure.

## Installation

```bash
npm install @mapprotocol/common-contracts
```

## Solidity Contracts

### BaseImplementation

Abstract base for all upgradeable protocol contracts. Combines UUPS proxy, pausable, and access control in one inheritance.

```solidity
import "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract MyContract is BaseImplementation {
    function initialize(address _admin) public initializer {
        __BaseImplementation_init(_admin);
    }
}
```

**Includes:**
- `UUPSUpgradeable` — proxy upgrade pattern
- `PausableUpgradeable` — emergency pause via `trigger()`
- `AccessManagedUpgradeable` — role-based function access
- `getImplementation()` — read current implementation address

### AuthorityManager

Extended `AccessManager` with enumerable role members. One instance per chain controls all protocol contracts.

```solidity
import "@mapprotocol/common-contracts/contracts/AuthorityManager.sol";
```

**Key functions:**
- `grantRole(roleId, account, delay)` — assign role
- `revokeRole(roleId, account)` — remove role
- `setTargetFunctionRole(target, selectors, roleId)` — restrict contract functions to a role
- `getRoleMembers(roleId)` — list all members of a role

## TypeScript Utilities

### Deployment

```typescript
import { getDeploymentByKey, saveDeployment, resolveDeploymentEnv } from "@mapprotocol/common-contracts/utils/deployment";

// Read deployed address (defaults to <cwd>/deployments/deploy.json)
const addr = await getDeploymentByKey("Bsc", "Gateway");

// With custom suffix and path
const addr = await getDeploymentByKey("Bsc", "Gateway", { suffix: "main", basePath: "./my-deployments" });

// Save deployment
await saveDeployment("Bsc", "Gateway", "0x...");
```

### Tron Interaction

```typescript
import { createTronWeb, tronDeploy, getTronContract, tronToHex, tronFromHex } from "@mapprotocol/common-contracts/utils/tronHelper";

// Address conversion (pure, no RPC needed)
const hex = tronToHex("TXyz...");        // -> "0x..."
const base58 = tronFromHex("0x...");     // -> "TXyz..."

// Deploy contract on Tron
const tronWeb = createTronWeb({ rpcUrl: "https://api.trongrid.io", privateKey: "..." });
const addr = await tronDeploy(tronWeb, artifacts, "MyContract", [arg1, arg2]);

// Read-only (no privateKey needed)
const readOnly = createTronWeb({ rpcUrl: "https://api.trongrid.io" });
const contract = await getTronContract(readOnly, artifacts, "MyContract", addr);
```

### Address Encoding

```typescript
import { addressToHex, isTronAddress, isSolanaChain } from "@mapprotocol/common-contracts/utils/addressCodec";

// Auto-detect format and convert to hex
addressToHex("0xAbC...");              // EVM -> lowercase hex
addressToHex("TXyz...");              // Tron -> extract 20-byte address
addressToHex("So11111...");           // Solana -> full base58 decode

// Type checks
isTronAddress("TXyz...");             // true (validates 0x41 prefix byte)
isSolanaChain("Sol");                 // true
```

## Forge Script Base

For monorepo projects, `script/Base.s.sol` provides deployment primitives:

```solidity
import {BaseScript} from "../../common/script/Base.s.sol";

contract MyDeploy is BaseScript {
    function run() public broadcast {
        // CREATE2 factory deployment (deterministic address)
        address addr = deployByFactory("my_salt", type(MyContract).creationCode, abi.encode(arg));

        // Check factory availability
        require(isFactoryAvailable(), "no factory on this chain");

        // UUPS proxy upgrade
        upgradeProxy(proxyAddr, newImplAddr);

        // Deploy new impl + upgrade in one step
        deployAndUpgrade(proxyAddr, type(MyContractV2).creationCode);
    }
}
```

## Development

```bash
# Build
forge build                  # Foundry
npm run build:hardhat        # Hardhat + TypeChain

# Test
forge test
forge test --gas-report

# Format
forge fmt

# Publish
npm run prepublishOnly       # clean + build + typecheck
npm publish
```

## Package Contents

| Path | Description |
|------|-------------|
| `contracts/**/*.sol` | Solidity source files |
| `artifacts/**/*.json` | Compiled ABI + bytecode |
| `typechain-types/**/*` | TypeChain generated types |
| `utils/*.ts` | Shared TypeScript utilities |

## Requirements

- Solidity ^0.8.20
- Node.js >= 18
- OpenZeppelin Contracts 5.4.0

## License

MIT

## Links

- [Repository](https://github.com/mapprotocol/mapo-contracts-v2/tree/main/common)
- [Issues](https://github.com/mapprotocol/mapo-contracts-v2/issues)
- [MAP Protocol](https://mapprotocol.io)
