/**
 * @mapprotocol/common-contracts/utils
 *
 * Shared TypeScript utilities for MAP Protocol contract operations.
 *
 * Quick start:
 *   const deployer = createDeployer(hre, { autoVerify: true });
 *   await deployer.deploy("MyContract", [arg1], "optional_salt");
 *   await deployer.deployProxy("MyContract", [initArg], "optional_salt");
 *   await deployer.upgrade("MyContract", proxyAddr);
 */

// Unified deployer — recommended entry point for deploy/upgrade/verify
export {
    createDeployer,
    type Deployer,
    type DeployResult,
    type DeployProxyResult,
    type DeployerOptions
} from "./deployer";

// Deploy record — deploy.json address management
export {
    resolveDeploymentEnv,
    getDeploymentByKey,
    hasDeployment,
    saveDeployment,
    type DeploymentOptions
} from "./deployRecord";

// Contract verification
export { verify, type VerifyOptions } from "./verifier";

// Address encoding
export { addressToHex, isBase58, isTronAddress, isSolanaChain } from "./addressCodec";

// Tron utilities
export { tronFromHex, tronToHex, isTronNetwork, createTronWeb, getTronContract, type TronConfig, type TronAddress } from "./tronHelper";
