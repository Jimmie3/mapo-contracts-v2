import { isTronNetwork, TronClient } from "./tronHelper";
import { evmDeploy, evmDeployProxy, evmUpgradeProxy } from "./evmHelper";
import { verify as _verify } from "./verifier";

/**
 * Unified deployer — auto-routes to EVM or Tron based on network name.
 *
 * Usage in hardhat tasks:
 *   const deployer = createDeployer(hre, { autoVerify: true });
 *   let addr = await deployer.deploy("Gateway", [admin], salt);
 *   let { proxy, implementation } = await deployer.deployProxy("Gateway", [admin], salt);
 *   let newImpl = await deployer.upgrade("Gateway", proxyAddr);
 */

export interface DeployerOptions {
    /**
     * Auto-verify contracts after deploy/upgrade.
     * Failures are logged as warnings, never thrown — call deployer.verify() for explicit error handling.
     * Defaults to false.
     */
    autoVerify?: boolean;
}

export interface DeployResult {
    address: string;       // EVM: 0x hex address. Tron: base58 (T...) address.
    hex?: string;          // Tron only: 0x hex address. Undefined on EVM.
}

export interface DeployProxyResult {
    proxy: string;         // proxy address (0x hex for EVM, base58 for Tron)
    implementation: string; // impl address
    proxyHex?: string;     // Tron hex
    implementationHex?: string; // Tron hex
}

export interface Deployer {
    /**
     * Deploy a contract.
     * @param contractName - artifact name
     * @param args - constructor arguments as raw values
     * @param salt - "" or omitted = direct deploy; non-empty string = CREATE2 factory (deterministic address)
     */
    deploy(contractName: string, args?: any[], salt?: string): Promise<DeployResult>;
    deployProxy(contractName: string, initArgs?: any[], salt?: string): Promise<DeployProxyResult>;
    upgrade(contractName: string, proxyAddr: string): Promise<DeployResult>;
    /** Verify explicitly (throws on failure, unlike autoVerify which only warns). */
    verify(contractName: string, address: string, constructorArgs?: any[], contractPath?: string): Promise<void>;
    isTron: boolean;
    network: string;
}

/**
 * Create a unified deployer that auto-routes to EVM or Tron based on network.
 * @param hre - hardhat runtime environment
 * @param opts - options (autoVerify: auto-verify after deploy, defaults to false)
 */
export function createDeployer(hre: any, opts: DeployerOptions = {}): Deployer {
    const network = hre.network.name;
    const isTron = isTronNetwork(network);
    const autoVerify = opts.autoVerify || false;

    async function tryVerify(contractName: string, address: string, constructorArgs?: any[], contractPath?: string) {
        if (!autoVerify) return;
        try {
            await _verify(hre, { contractName, address, constructorArgs, contractPath });
        } catch (e: any) {
            console.log(`[warn] auto-verify failed: ${e.message || e}`);
        }
    }

    if (isTron) {
        const client = TronClient.fromHre(hre);

        return {
            isTron: true,
            network,

            async deploy(contractName, args = [], salt = "") {
                let result = await client.deploy(hre.artifacts, contractName, args, salt);
                await tryVerify(contractName, result.base58, args);
                return { address: result.base58, hex: result.hex };
            },

            async deployProxy(contractName, initArgs = [], salt = "") {
                let result = await client.deployProxy(hre.artifacts, contractName, initArgs, salt);
                await tryVerify(contractName, result.implementation.base58);
                return {
                    proxy: result.proxy.base58,
                    implementation: result.implementation.base58,
                    proxyHex: result.proxy.hex,
                    implementationHex: result.implementation.hex,
                };
            },

            async upgrade(contractName, proxyAddr) {
                let result = await client.upgradeProxy(hre.artifacts, contractName, proxyAddr);
                await tryVerify(contractName, result.base58);
                return { address: result.base58, hex: result.hex };
            },

            async verify(contractName, address, constructorArgs, contractPath) {
                await _verify(hre, { contractName, address, constructorArgs, contractPath });
            },
        };
    }

    // EVM
    const { ethers, artifacts } = hre;
    return {
        isTron: false,
        network,

        async deploy(contractName, args = [], salt = "") {
            let addr = await evmDeploy(ethers, artifacts, contractName, args, salt);
            await tryVerify(contractName, addr, args);
            return { address: addr };
        },

        async deployProxy(contractName, initArgs = [], salt = "") {
            let result = await evmDeployProxy(ethers, artifacts, contractName, initArgs, salt);
            await tryVerify(contractName, result.implementation);
            return { proxy: result.proxy, implementation: result.implementation };
        },

        async upgrade(contractName, proxyAddr) {
            let addr = await evmUpgradeProxy(ethers, contractName, proxyAddr);
            await tryVerify(contractName, addr);
            return { address: addr };
        },

        async verify(contractName, address, constructorArgs, contractPath) {
            await _verify(hre, { contractName, address, constructorArgs, contractPath });
        },
    };
}
