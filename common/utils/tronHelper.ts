let TronWeb = require("tronweb");

// ============================================================
// Pure address conversion — no RPC, no private key needed
// ============================================================

export function tronFromHex(hex: string): string {
    if (hex.startsWith("T") && hex.length === 34) return hex;
    return TronWeb.address.fromHex(hex);
}

export function tronToHex(addr: string): string {
    if (addr.startsWith("0x") && addr.length === 42) return addr;
    return TronWeb.address.toHex(addr).replace(/^(41)/, "0x");
}

export function isTronNetwork(network: string): boolean {
    return network === "Tron" || network === "tron_test" || network === "Tron_test";
}

// ============================================================
// TronWeb instance creation
// ============================================================

export interface TronConfig {
    rpcUrl: string;
    privateKey?: string; // optional — omit for read-only operations
}

export function createTronWeb(config: TronConfig) {
    const opts: any = { fullHost: config.rpcUrl };
    if (config.privateKey) {
        opts.privateKey = config.privateKey;
    }
    return new TronWeb(opts);
}

// ============================================================
// Contract interaction — requires tronWeb instance
// ============================================================

export interface TronAddress {
    hex: string;    // 0x-prefixed address
    base58: string; // T-prefixed address
}

/**
 * Deploy contract on Tron. If salt is provided, uses CREATE2 factory for deterministic address.
 * @param salt - optional salt string for factory deployment
 * @returns { hex, base58 } deployed address in both formats
 */
export async function tronDeploy(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    args: any[] = [],
    salt: string = "",
    feeLimit: number = 15_000_000_000
): Promise<TronAddress> {
    if (salt) {
        const { tronDeployByFactory } = require("./factory");
        const hex: string = await tronDeployByFactory(tronWeb, artifacts, contractName, salt, args, feeLimit);
        return { hex, base58: tronFromHex(hex) };
    }

    let c = await artifacts.readArtifact(contractName);
    console.log("deploy address is:", tronWeb.defaultAddress.base58);
    let instance = await tronWeb.contract().new({
        abi: c.abi,
        bytecode: c.bytecode,
        feeLimit,
        callValue: 0,
        parameters: args,
    });
    let raw = instance.address; // 41-prefixed hex
    let hex = raw.replace(/^41/, "0x");
    let base58 = tronWeb.address.fromHex(raw);
    console.log(`${contractName} deployed: ${base58} (${hex})`);
    return { hex, base58 };
}

/**
 * Deploy implementation + ERC1967 proxy on Tron.
 * If salt is provided, proxy is deployed via factory.
 * @returns { proxy, implementation } both as TronAddress
 */
export async function tronDeployProxy(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    initArgs: any[] = [],
    salt: string = "",
    feeLimit: number = 15_000_000_000
): Promise<{ proxy: TronAddress; implementation: TronAddress }> {
    // Deploy implementation
    let implementation = await tronDeploy(tronWeb, artifacts, contractName, [], "", feeLimit);
    console.log(`${contractName} implementation: ${implementation.base58} (${implementation.hex})`);

    // Encode initialize call
    let artifact = await artifacts.readArtifact(contractName);
    const iface = new (require("ethers").Interface)(artifact.abi);
    const initData = iface.encodeFunctionData("initialize", initArgs);

    // Deploy proxy
    let proxy = await tronDeploy(tronWeb, artifacts, "ERC1967Proxy", [implementation.hex, initData], salt, feeLimit);
    console.log(`${contractName} proxy: ${proxy.base58} (${proxy.hex})`);

    return { proxy, implementation };
}

/**
 * Upgrade a UUPS proxy to a new implementation on Tron
 * @returns new implementation TronAddress
 */
export async function tronUpgradeProxy(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    proxyAddr: string,
    feeLimit: number = 15_000_000_000
): Promise<TronAddress> {
    // Deploy new implementation
    let impl = await tronDeploy(tronWeb, artifacts, contractName, [], "", feeLimit);
    console.log(`${contractName} new implementation: ${impl.base58} (${impl.hex})`);

    // Upgrade proxy
    let proxyContract = await getTronContract(tronWeb, artifacts, "BaseImplementation", proxyAddr);
    let oldImpl = await proxyContract.getImplementation().call();
    console.log(`old implementation: ${tronFromHex(oldImpl)}`);

    await proxyContract.upgradeToAndCall(impl.hex, "0x").send({ feeLimit });

    let newImpl = await proxyContract.getImplementation().call();
    console.log(`${contractName} upgraded: ${tronFromHex(oldImpl)} -> ${tronFromHex(newImpl)}`);
    return impl;
}

export async function getTronContract(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    addr: string
): Promise<any> {
    console.log("operator address is:", tronWeb.defaultAddress.base58);
    let C = await artifacts.readArtifact(contractName);
    return tronWeb.contract(C.abi, addr);
}

export function getTronDeployer(tronWeb: any, hex: boolean = false): string {
    if (hex) {
        return tronWeb.defaultAddress.hex.replace(/^(41)/, "0x");
    }
    return tronWeb.defaultAddress.base58;
}
