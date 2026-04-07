let fs = require("fs");
let path = require("path");
import "@nomicfoundation/hardhat-ethers";

export function getNetworkName(network: string) {
    if (network.indexOf("test") > 0) return network;
    let suffix = process.env.NETWORK_SUFFIX;
    if (suffix === "main") {
        return network + "_" + "main";
    } else {
        return network + "_" + "prod";
    }
}

type Deployment = {
    [network: string]: {
        [key: string]: any;
    };
};

export async function getDeploymentByKey(network: string, key: string) {
    network = getNetworkName(network);
    let deployment = await readDeploymentFromFile(network);
    let deployAddress = deployment[network][key];
    if (!deployAddress) throw `no ${key} deployment in ${network}`;
    return deployAddress;
}

async function readDeploymentFromFile(network: string): Promise<Deployment> {
    let p = path.join(__dirname, "../../deployments/deploy.json");
    let deploy: Deployment;
    if (!fs.existsSync(p)) {
        deploy = {};
        deploy[network] = {};
    } else {
        let rawdata = fs.readFileSync(p, "utf-8");
        deploy = JSON.parse(rawdata);
        if (!deploy[network]) {
            deploy[network] = {};
        }
    }
    return deploy;
}

export async function saveDeployment(network: string, key: string, addr: string) {
    network = getNetworkName(network);
    let deployment = await readDeploymentFromFile(network);
    deployment[network][key] = addr;
    let p = path.join(__dirname, "../../deployments/deploy.json");
    await folder("../../deployments/");
    fs.writeFileSync(p, JSON.stringify(deployment, null, "\t"));
}

const folder = async (reaPath: string) => {
    const absPath = path.resolve(__dirname, reaPath);
    try {
        await fs.promises.stat(absPath);
    } catch (e) {
        await fs.promises.mkdir(absPath, { recursive: true });
    }
};