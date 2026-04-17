let TronWeb = require("tronweb");

// ============================================================
// Pure address conversion — no RPC, no private key needed
// ============================================================

/** Convert hex address to Tron base58 format. Returns as-is if already base58. */
export function tronFromHex(hex: string): string {
    if (hex.startsWith("T") && hex.length === 34) return hex;
    return TronWeb.address.fromHex(hex);
}

/** Convert Tron base58 address to 0x-prefixed hex. Returns as-is if already hex. */
export function tronToHex(addr: string): string {
    if (addr.startsWith("0x") && addr.length === 42) return addr;
    return TronWeb.address.toHex(addr).replace(/^(41)/, "0x");
}

// Tron chainIds: mainnet 728126428, nile testnet 3448148188
const TRON_CHAIN_IDS = [728126428, 3448148188];

/** Check if a network name or chainId belongs to Tron (case-insensitive). */
export function isTronNetwork(networkOrChainId: string | number): boolean {
    if (typeof networkOrChainId === "number") {
        return TRON_CHAIN_IDS.includes(networkOrChainId);
    }
    return networkOrChainId.toLowerCase().startsWith("tron");
}

export interface TronAddress {
    hex: string;    // 0x-prefixed address
    base58: string; // T-prefixed address
}

// ============================================================
// TronClient
// ============================================================

/**
 * TronClient — encapsulates tronWeb instance, provides high-level contract operations.
 *
 * Usage:
 *   // From hardhat runtime (recommended in tasks)
 *   let client = TronClient.fromHre(hre);
 *
 *   // Manual — with rpc and private key
 *   let client = new TronClient("https://api.trongrid.io", "your_private_key");
 *
 *   // Read-only — no private key
 *   let client = new TronClient("https://api.trongrid.io");
 *
 *   // Contract interaction
 *   let gw = await client.getContract(artifacts, "Gateway", addr);
 *   let wtoken = await gw.wToken().call();                      // read
 *   await gw.setWtoken(client.toHex(wtoken)).sendAndWait();     // write + wait
 *
 *   // Deploy
 *   let { hex, base58 } = await client.deploy(artifacts, "Gateway");
 *   let { proxy, implementation } = await client.deployProxy(artifacts, "Gateway", [admin]);
 *
 *   // Upgrade
 *   await client.upgradeProxy(artifacts, "Gateway", proxyAddr);
 */
export class TronClient {
    private tronWeb: any;
    private connected: boolean = false;

    /**
     * Create a TronClient with explicit rpcUrl.
     * @param rpcUrl - Tron full host URL (e.g. "https://api.trongrid.io")
     * @param privateKey - optional, omit for read-only operations
     */
    constructor(rpcUrl: string, privateKey?: string) {
        const opts: any = { fullHost: rpcUrl };
        if (privateKey) {
            // TronWeb doesn't accept 0x prefix on private keys
            opts.privateKey = privateKey.startsWith("0x") ? privateKey.slice(2) : privateKey;
        }
        this.tronWeb = new TronWeb(opts);
    }

    /**
     * Create TronClient from hardhat runtime environment.
     * Reads rpcUrl and privateKey from hre.network.config. Verifies RPC connectivity.
     */
    static fromHre(hre: any): TronClient {
        const config = hre.network.config;
        let rpcUrl: string = config.url;
        let privateKey = Array.isArray(config.accounts) ? config.accounts[0] : undefined;
        if (!rpcUrl) throw new Error(`no rpc url configured for network ${hre.network.name}`);
        // Hardhat config uses JSON-RPC path (e.g. /jsonrpc), TronWeb needs base URL
        rpcUrl = rpcUrl.replace(/\/(jsonrpc|wallet|solidity)\/?$/i, "");
        // TronWeb doesn't accept 0x prefix on private keys
        if (privateKey && privateKey.startsWith("0x")) {
            privateKey = privateKey.slice(2);
        }
        return new TronClient(rpcUrl, privateKey);
    }

    /** Verify RPC is reachable. Uses getNowBlock which is widely supported. */
    private async _checkConnection(): Promise<void> {
        if (this.connected) return;
        try {
            // getNowBlock calls /wallet/getnowblock — more universally supported than getNodeInfo
            await this.tronWeb.trx.getCurrentBlock();
            this.connected = true;
        } catch (e: any) {
            const url = this.tronWeb.fullNode?.host || "unknown";
            throw new Error(
                `TronClient: cannot connect to ${url}. ` +
                `Ensure the URL is a valid TronWeb full host (e.g. "https://api.trongrid.io") and is reachable. ` +
                `Error: ${e.message || e}`
            );
        }
    }

    /** Lazy connection check — called before first contract operation. */
    private async _ensureConnected(): Promise<void> {
        if (!this.connected) await this._checkConnection();
    }

    /** Get the default operator address in base58 format. */
    get defaultAddress(): string {
        return this.tronWeb.defaultAddress.base58;
    }

    /** Convert Tron base58 address to 0x hex. */
    toHex(addr: string): string {
        return tronToHex(addr);
    }

    /** Convert 0x hex to Tron base58 address. */
    fromHex(hex: string): string {
        return tronFromHex(hex);
    }

    /**
     * Get a contract instance. Write methods have .sendAndWait() attached.
     * @param artifacts - hardhat artifacts (hre.artifacts)
     * @param contractName - contract name (e.g. "Gateway")
     * @param addr - contract address (base58 or hex)
     */
    async getContract(artifacts: any, contractName: string, addr: string): Promise<any> {
        await this._ensureConnected();
        console.log("operator address is:", this.defaultAddress);
        const artifact = await artifacts.readArtifact(contractName);
        const contract = await this.tronWeb.contract(artifact.abi, addr);
        return this._wrapContract(contract);
    }

    /**
     * Deploy contract. If salt is provided, uses CREATE2 factory.
     * @param artifacts - hardhat artifacts
     * @param contractName - contract name to deploy
     * @param args - constructor arguments
     * @param salt - optional CREATE2 salt for deterministic address
     * @param feeLimit - Tron fee limit (default 15 TRX)
     */
    async deploy(
        artifacts: any,
        contractName: string,
        args: any[] = [],
        salt: string = "",
        feeLimit: number = 15_000_000_000
    ): Promise<TronAddress> {
        await this._ensureConnected();
        return tronDeploy(this.tronWeb, artifacts, contractName, args, salt, feeLimit);
    }

    /**
     * Deploy implementation + ERC1967 proxy. If salt is provided, proxy uses factory.
     * @param artifacts - hardhat artifacts
     * @param contractName - implementation contract name
     * @param initArgs - initialize() function arguments
     * @param salt - optional CREATE2 salt for proxy
     * @param feeLimit - Tron fee limit
     */
    async deployProxy(
        artifacts: any,
        contractName: string,
        initArgs: any[] = [],
        salt: string = "",
        feeLimit: number = 15_000_000_000
    ): Promise<{ proxy: TronAddress; implementation: TronAddress }> {
        await this._ensureConnected();
        return tronDeployProxy(this.tronWeb, artifacts, contractName, initArgs, salt, feeLimit);
    }

    /**
     * Upgrade a UUPS proxy to a new implementation.
     * @param artifacts - hardhat artifacts
     * @param contractName - new implementation contract name
     * @param proxyAddr - proxy address to upgrade
     * @param feeLimit - Tron fee limit
     */
    async upgradeProxy(
        artifacts: any,
        contractName: string,
        proxyAddr: string,
        feeLimit: number = 15_000_000_000
    ): Promise<TronAddress> {
        await this._ensureConnected();
        return tronUpgradeProxy(this.tronWeb, artifacts, contractName, proxyAddr, feeLimit);
    }

    /**
     * Wait for a transaction to be confirmed on-chain.
     * @param txId - transaction hash from .send()
     */
    async waitForTx(txId: string, retries: number = 20, interval: number = 3000): Promise<any> {
        return waitForTx(this.tronWeb, txId, retries, interval);
    }

    /** Wrap contract methods — adds .sendAndWait() to write methods. */
    private _wrapContract(contract: any): any {
        const tronWeb = this.tronWeb;
        return new Proxy(contract, {
            get(target, prop) {
                const original = target[prop];
                if (typeof original !== "function") return original;

                return (...args: any[]) => {
                    const methodCall = original.apply(target, args);
                    if (methodCall && typeof methodCall.send === "function") {
                        methodCall.sendAndWait = (opts?: Record<string, any>) =>
                            sendAndWait(methodCall, tronWeb, opts);
                    }
                    return methodCall;
                };
            }
        });
    }
}

// ============================================================
// Low-level functions (used internally by TronClient)
// ============================================================

/** @internal Deploy contract on Tron. If salt is provided, uses CREATE2 factory. */
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

    const artifact = await artifacts.readArtifact(contractName);
    console.log("deploy address is:", tronWeb.defaultAddress.base58);
    const instance = await tronWeb.contract().new({
        abi: artifact.abi,
        bytecode: artifact.bytecode,
        feeLimit,
        callValue: 0,
        parameters: args,
    });
    const rawAddress = instance.address; // 41-prefixed hex
    const hex = rawAddress.replace(/^41/, "0x");
    const base58 = tronWeb.address.fromHex(rawAddress);
    console.log(`${contractName} deployed: ${base58} (${hex})`);
    return { hex, base58 };
}

/** @internal Deploy implementation + ERC1967 proxy on Tron. */
export async function tronDeployProxy(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    initArgs: any[] = [],
    salt: string = "",
    feeLimit: number = 15_000_000_000
): Promise<{ proxy: TronAddress; implementation: TronAddress }> {
    const implementation = await tronDeploy(tronWeb, artifacts, contractName, [], "", feeLimit);
    console.log(`${contractName} implementation: ${implementation.base58} (${implementation.hex})`);

    // Wait for implementation to be fully confirmed before deploying proxy
    if (salt) {
        console.log("waiting for implementation to be indexed...");
        await new Promise(r => setTimeout(r, 5000));
    }

    const artifact = await artifacts.readArtifact(contractName);
    const iface = new (require("ethers").Interface)(artifact.abi);
    const initData = iface.encodeFunctionData("initialize", initArgs);

    const proxy = await tronDeploy(tronWeb, artifacts, "ERC1967Proxy", [implementation.hex, initData], salt, feeLimit);
    console.log(`${contractName} proxy: ${proxy.base58} (${proxy.hex})`);

    return { proxy, implementation };
}

/** @internal Upgrade a UUPS proxy to a new implementation on Tron. */
export async function tronUpgradeProxy(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    proxyAddr: string,
    feeLimit: number = 15_000_000_000
): Promise<TronAddress> {
    const impl = await tronDeploy(tronWeb, artifacts, contractName, [], "", feeLimit);
    console.log(`${contractName} new implementation: ${impl.base58} (${impl.hex})`);

    const artifact = await artifacts.readArtifact("BaseImplementation");
    const proxyContract = await tronWeb.contract(artifact.abi, proxyAddr);
    const oldImpl = await proxyContract.getImplementation().call();
    console.log(`old implementation: ${tronFromHex(oldImpl)}`);

    await sendAndWait(proxyContract.upgradeToAndCall(impl.hex, "0x"), tronWeb, { feeLimit });

    const newImpl = await proxyContract.getImplementation().call();
    console.log(`${contractName} upgraded: ${tronFromHex(oldImpl)} -> ${tronFromHex(newImpl)}`);
    return impl;
}

/**
 * Send a tron contract call and wait for on-chain confirmation.
 * @param methodCall - tronweb contract method call (e.g. contract.setWtoken(addr))
 * @param tronWeb - tronweb instance for querying tx status
 * @param opts - send options (feeLimit, callValue, etc.)
 */
export async function sendAndWait(
    methodCall: any,
    tronWeb: any,
    opts: Record<string, any> = {}
): Promise<any> {
    const txId = await methodCall.send(opts);
    return waitForTx(tronWeb, txId);
}

/**
 * Wait for a Tron transaction to be confirmed on-chain.
 * @param tronWeb - tronweb instance
 * @param txId - transaction hash returned by .send()
 * @param retries - max poll attempts (default 20)
 * @param interval - poll interval in ms (default 3000)
 */
export async function waitForTx(
    tronWeb: any,
    txId: string,
    retries: number = 20,
    interval: number = 3000
): Promise<any> {
    console.log(`waiting for tx ${txId}...`);
    for (let i = 0; i < retries; i++) {
        const result = await tronWeb.trx.getTransactionInfo(txId);
        if (result && result.id) {
            if (result.receipt?.result === "SUCCESS") {
                console.log(`tx confirmed in block ${result.blockNumber}`);
                return result;
            }
            throw new Error(`tx failed: ${result.receipt?.result || "UNKNOWN"}`);
        }
        await new Promise(r => setTimeout(r, interval));
    }
    throw new Error(`tx not confirmed after ${retries} retries: ${txId}`);
}
