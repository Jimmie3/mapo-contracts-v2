# @mapprotocol/common-contracts

Shared smart contracts and TypeScript utilities for MAP Protocol's multi-chain infrastructure.

## Installation

```bash
npm install @mapprotocol/common-contracts
```

## Solidity Contracts

### BaseImplementation

Abstract base for all upgradeable protocol contracts (UUPS + Pausable + AccessManaged).

```solidity
import "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract MyContract is BaseImplementation {
    function initialize(address _admin) public initializer {
        __BaseImplementation_init(_admin);
    }
}
```

### AuthorityManager

Extended `AccessManager` with enumerable role members. One instance per chain controls all protocol contracts.

```solidity
import "@mapprotocol/common-contracts/contracts/AuthorityManager.sol";
```

## TypeScript Utilities

```typescript
import { createDeployer } from "@mapprotocol/common-contracts/utils/deployer";
import { getDeploymentByKey, saveDeployment } from "@mapprotocol/common-contracts/utils/deployRecord";
import { TronClient, tronToHex, tronFromHex } from "@mapprotocol/common-contracts/utils/tronHelper";
import { verify } from "@mapprotocol/common-contracts/utils/verifier";
import { addressToHex } from "@mapprotocol/common-contracts/utils/addressCodec";
```

### Quick Start

```typescript
// Unified deployer — auto-routes EVM / Tron
const deployer = createDeployer(hre, { autoVerify: true });
let result = await deployer.deploy("Gateway", [bridge, owner, wtoken]);
let proxy  = await deployer.deployProxy("Gateway", [admin]);

// Deploy record
const addr = getDeploymentByKey("Bsc", "Gateway", { env: "prod" });
saveDeployment("Bsc", "Gateway", "0x...", { env: "prod" });

// Tron client
let client = TronClient.fromHre(hre);
let gw = await client.getContract(hre.artifacts, "Gateway", addr);
await gw.setWtoken(client.toHex(wtoken)).sendAndWait();
let val = await gw.wToken().call();
```

See JSDoc in each module's source for full API details and edge cases.

## Forge Script Base

```solidity
import {BaseScript} from "@mapprotocol/common-contracts/script/base/Base.s.sol";

contract MyDeploy is BaseScript {
    function run() public broadcast {
        (address proxy, address impl) = deployProxy(type(MyContract).creationCode, initData);
        address addr = deployByFactory("my_salt", type(MyContract).creationCode, abi.encode(arg));
        deployAndUpgrade(proxyAddr, type(MyContractV2).creationCode);
        address relay = readDeployment("Relay");
        saveDeployment("Gateway", addr);
    }
}
```

## Development

```bash
forge build && forge test          # Solidity
npm run build:hardhat              # Hardhat + TypeChain
npm run build:utils                # TypeScript utilities
npm run prepublishOnly && npm publish
```

## License

MIT
