import { isTronNetwork, createTronWeb, tronDeploy, tronDeployProxy, tronUpgradeProxy, TronConfig, TronAddress } from "./tronHelper";
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
    autoVerify?: boolean;   // auto verify after deploy/upgrade, defaults to false
    tronConfig?: TronConfig;
}

export interface DeployResult {
    address: string;       // primary address (0x hex for EVM, base58 for Tron)
    hex?: string;          // 0x hex (Tron only, EVM same as address)
}

export interface DeployProxyResult {
    proxy: string;         // proxy address (0x hex for EVM, base58 for Tron)
    implementation: string; // impl address
    proxyHex?: string;     // Tron hex
    implementationHex?: string; // Tron hex
}

export interface Deployer {
    deploy(contractName: string, args?: any[], salt?: string): Promise<DeployResult>;
    deployProxy(contractName: string, initArgs?: any[], salt?: string): Promise<DeployProxyResult>;
    upgrade(contractName: string, proxyAddr: string): Promise<DeployResult>;
    verify(contractName: string, address: string, constructorArgs?: any[], contractPath?: string): Promise<void>;
    isTron: boolean;
    network: string;
}

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
        let tronConfig = opts.tronConfig;
        if (!tronConfig) {
            const rpcUrl = process.env.TRON_RPC_URL;
            const privateKey = process.env.TRON_PRIVATE_KEY;
            if (!rpcUrl || !privateKey) throw new Error("TRON_RPC_URL and TRON_PRIVATE_KEY required");
            tronConfig = { rpcUrl, privateKey };
        }
        const tronWeb = createTronWeb(tronConfig);

        return {
            isTron: true,
            network,

            async deploy(contractName, args = [], salt = "") {
                let result = await tronDeploy(tronWeb, hre.artifacts, contractName, args, salt);
                await tryVerify(contractName, result.base58, args);
                return { address: result.base58, hex: result.hex };
            },

            async deployProxy(contractName, initArgs = [], salt = "") {
                let result = await tronDeployProxy(tronWeb, hre.artifacts, contractName, initArgs, salt);
                await tryVerify(contractName, result.implementation.base58);
                return {
                    proxy: result.proxy.base58,
                    implementation: result.implementation.base58,
                    proxyHex: result.proxy.hex,
                    implementationHex: result.implementation.hex,
                };
            },

            async upgrade(contractName, proxyAddr) {
                let result = await tronUpgradeProxy(tronWeb, hre.artifacts, contractName, proxyAddr);
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
