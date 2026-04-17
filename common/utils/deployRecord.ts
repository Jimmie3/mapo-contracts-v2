/**
 * Deploy record — read/write deployed contract addresses from deploy.json
 *
 * Structure:
 *   {
 *     "prod": { "Mapo": { "Relay": "0x..." }, "Bsc": { "Gateway": "0x..." } },
 *     "main": { "Mapo": { "Relay": "0x..." } },
 *     "test": { "Mapo": { "Relay": "0x..." } }
 *   }
 */
let fs = require("fs");
let path = require("path");

type DeployData = {
    [env: string]: {
        [chain: string]: {
            [key: string]: string;
        };
    };
};

export interface DeploymentPath {
    env: string;    // "prod", "main", "test"
    chain: string;  // "Mapo", "Bsc", "Tron"
}

export interface DeploymentOptions {
    basePath?: string;  // defaults to <cwd>/deployments/
    suffix?: string;    // defaults to "prod"
}

function defaultDeployPath(): string {
    return path.join(process.cwd(), "deployments");
}

/**
 * Resolve deployment path from hardhat network name.
 * @param network - hardhat network name (e.g. "Bsc", "Mapo_test", "tron_test")
 * @param suffix - environment suffix (e.g. "prod", "main"), defaults to "prod"
 * @returns { env, chain } for deploy.json lookup
 */
export function resolveDeploymentPath(network: string, suffix: string = "prod"): DeploymentPath {
    if (network.toLowerCase().includes("test")) {
        const chain = network.replace(/_?test$/i, "");
        return { env: "test", chain: chain.charAt(0).toUpperCase() + chain.slice(1) };
    }
    return { env: suffix, chain: network };
}

/**
 * Read a deployed contract address from deploy.json.
 * @param network - hardhat network name
 * @param key - contract key (e.g. "Gateway", "Authority")
 * @param opts - optional basePath and suffix overrides
 */
export async function getDeploymentByKey(network: string, key: string, opts?: DeploymentOptions): Promise<string> {
    const deployPath = opts?.basePath || defaultDeployPath();
    const { env, chain } = resolveDeploymentPath(network, opts?.suffix);
    const data = await readDeployFile(deployPath);
    const addr = data[env]?.[chain]?.[key];
    if (!addr) throw new Error(`no ${key} deployment in ${env}.${chain}`);
    return addr;
}

/**
 * Check if a contract address exists and is valid in deploy.json.
 * @param network - hardhat network name
 * @param key - contract key
 * @param opts - optional basePath and suffix overrides
 */
export async function hasDeployment(network: string, key: string, opts?: DeploymentOptions): Promise<boolean> {
    try {
        const deployPath = opts?.basePath || defaultDeployPath();
        const { env, chain } = resolveDeploymentPath(network, opts?.suffix);
        const data = await readDeployFile(deployPath);
        const addr = data[env]?.[chain]?.[key];
        return !!addr && addr.length > 2 && addr !== "0x";
    } catch {
        return false;
    }
}

/**
 * Save a deployed contract address to deploy.json.
 * @param network - hardhat network name
 * @param key - contract key (e.g. "Gateway")
 * @param addr - deployed address
 * @param opts - optional basePath and suffix overrides
 */
export async function saveDeployment(network: string, key: string, addr: string, opts?: DeploymentOptions): Promise<void> {
    const deployPath = opts?.basePath || defaultDeployPath();
    const { env, chain } = resolveDeploymentPath(network, opts?.suffix);
    const data = await readDeployFile(deployPath);
    if (!data[env]) data[env] = {};
    if (!data[env][chain]) data[env][chain] = {};
    data[env][chain][key] = addr;
    const filePath = path.resolve(deployPath, "deploy.json");
    await ensureDir(deployPath);
    await fs.promises.writeFile(filePath, JSON.stringify(data, null, "\t"));
}

async function readDeployFile(basePath: string): Promise<DeployData> {
    const filePath = path.resolve(basePath, "deploy.json");
    try {
        const rawdata = await fs.promises.readFile(filePath, "utf-8");
        return JSON.parse(rawdata);
    } catch {
        return {};
    }
}

async function ensureDir(dirPath: string): Promise<void> {
    const absPath = path.resolve(dirPath);
    try {
        await fs.promises.stat(absPath);
    } catch {
        await fs.promises.mkdir(absPath, { recursive: true });
    }
}
