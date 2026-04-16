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

export async function tronDeploy(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    args: any[] = [],
    feeLimit: number = 15_000_000_000
): Promise<string> {
    let c = await artifacts.readArtifact(contractName);
    console.log("deploy address is:", tronWeb.defaultAddress.base58);
    let instance = await tronWeb.contract().new({
        abi: c.abi,
        bytecode: c.bytecode,
        feeLimit,
        callValue: 0,
        parameters: args,
    });
    let hex = instance.address; // 41-prefixed hex
    let base58 = tronWeb.address.fromHex(hex);
    console.log(`${contractName} deployed: ${base58} (${hex})`);
    return hex.replace(/^41/, "0x");
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
