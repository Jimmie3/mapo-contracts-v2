let fs = require("fs");
let path = require("path");

type Deployment = {
    [network: string]: {
        [key: string]: any;
    };
};

export interface DeploymentOptions {
    basePath?: string;  // defaults to <cwd>/deployments/
    suffix?: string;    // defaults to "prod"
}

// Default deployments path: <project_root>/deployments/
function defaultDeployPath(): string {
    return path.join(process.cwd(), "deployments");
}

// Resolve deployment environment key from network name
// e.g., "Bsc" + "prod" -> "Bsc_prod", "Bsc_test" -> "Bsc_test"
export function resolveDeploymentEnv(network: string, suffix: string = "prod"): string {
    if (network.includes("test")) return network;
    return `${network}_${suffix}`;
}

export async function getDeploymentByKey(network: string, key: string, opts?: DeploymentOptions): Promise<string> {
    const deployPath = opts?.basePath || defaultDeployPath();
    const env = resolveDeploymentEnv(network, opts?.suffix);
    const deployment = await readDeploymentFromFile(deployPath, env);
    const addr = deployment[env]?.[key];
    if (!addr) throw `no ${key} deployment in ${env}`;
    return addr;
}

export async function hasDeployment(network: string, key: string, opts?: DeploymentOptions): Promise<boolean> {
    try {
        const deployPath = opts?.basePath || defaultDeployPath();
        const env = resolveDeploymentEnv(network, opts?.suffix);
        const deployment = await readDeploymentFromFile(deployPath, env);
        const addr = deployment[env]?.[key];
        return !!addr && addr.length > 2 && addr !== "0x";
    } catch {
        return false;
    }
}

export async function saveDeployment(network: string, key: string, addr: string, opts?: DeploymentOptions): Promise<void> {
    const deployPath = opts?.basePath || defaultDeployPath();
    const env = resolveDeploymentEnv(network, opts?.suffix);
    const deployment = await readDeploymentFromFile(deployPath, env);
    deployment[env][key] = addr;
    const p = path.resolve(deployPath, "deploy.json");
    await ensureDir(deployPath);
    fs.writeFileSync(p, JSON.stringify(deployment, null, "\t"));
}

async function readDeploymentFromFile(basePath: string, env: string): Promise<Deployment> {
    const p = path.resolve(basePath, "deploy.json");
    let deploy: Deployment;
    if (!fs.existsSync(p)) {
        deploy = {};
        deploy[env] = {};
    } else {
        const rawdata = fs.readFileSync(p, "utf-8");
        deploy = JSON.parse(rawdata);
        if (!deploy[env]) {
            deploy[env] = {};
        }
    }
    return deploy;
}

async function ensureDir(dirPath: string): Promise<void> {
    const absPath = path.resolve(dirPath);
    try {
        await fs.promises.stat(absPath);
    } catch (e) {
        await fs.promises.mkdir(absPath, { recursive: true });
    }
}
