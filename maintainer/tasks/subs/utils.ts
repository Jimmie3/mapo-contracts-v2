import "@nomicfoundation/hardhat-ethers";

import {
    getDeploymentByKey as _getDeploymentByKey,
    saveDeployment as _saveDeployment
} from "@mapprotocol/common-contracts/utils/deployRecord";

function getEnv() {
    const env = process.env.NETWORK_ENV;
    if (!env) throw new Error("NETWORK_ENV is required. Set to test/prod/main in .env");
    return env;
}

export async function getDeployment(network: string, key: string) {
    return _getDeploymentByKey(network, key, { env: getEnv() });
}

export async function saveDeployment(network: string, key: string, addr: string) {
    return _saveDeployment(network, key, addr, { env: getEnv() });
}
