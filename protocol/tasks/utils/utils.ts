let fs = require("fs");
let path = require("path");
import "@nomicfoundation/hardhat-ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime";

import {
    resolveDeploymentPath as _resolveDeploymentPath,
    getDeploymentByKey as _getDeploymentByKey,
    hasDeployment as _hasDeployment,
    saveDeployment as _saveDeployment
} from "@mapprotocol/common-contracts/utils/deployRecord";

// Read NETWORK_ENV, default to "test" (safe default)
function getEnv() {
    const env = process.env.NETWORK_ENV;
    if (!env) throw new Error("NETWORK_ENV is required. Set to test/prod/main in .env");
    return env;
}

export function resolveDeploymentPath(network: string) {
    return _resolveDeploymentPath(network, getEnv());
}
export async function getDeploymentByKey(network: string, key: string) {
    return _getDeploymentByKey(network, key, { env: getEnv() });
}
export async function hasDeployment(network: string, key: string) {
    return _hasDeployment(network, key, { env: getEnv() });
}
export async function saveDeployment(network: string, key: string, addr: string) {
    return _saveDeployment(network, key, addr, { env: getEnv() });
}

// ============================================================
// Protocol-specific config readers
// ============================================================

type Token = {
    name: string,
    addr: string,
    decimals: string,
    bridgeAble: boolean,
    mintAble: boolean,
    burnFrom: boolean
}

type ChainToken = {
    [network: string]: {
        chainId: number,
        lastScanBlock: number,
        updateGasFeeGap: number,
        confirmCount: number,
        minGasCallOnReceive: number,
        chainType: string,
        gasToken: string,
        baseFeeToken: string,
        transferFailedReceiver: string
        tokens: Token[]
    }
}

export async function getConfigration(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "configration.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let rawdata = fs.readFileSync(p, "utf-8");
    return JSON.parse(rawdata);
}

export async function getAllChainTokens(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "chainTokens.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let chainTokens: ChainToken;
    let rawdata = fs.readFileSync(p, "utf-8");
    chainTokens = JSON.parse(rawdata);
    return chainTokens;
}

export async function getChainTokenByNetwork(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "chainTokens.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let chainTokens: ChainToken;
    let rawdata = fs.readFileSync(p, "utf-8");
    chainTokens = JSON.parse(rawdata);
    return chainTokens[network];
}

type TokenRegister = {
    vaultFeeRate: VaultFeeRate,
    balanceFeeRate: BalanceFeeRate,
    tokens: TokenInfo[]
}

type ChainWeight = {
    chainId: number,
    weight: number
}

type RelayOutMinAmount = {
    chainId: number,
    minAmount: string
}

type TokenInfo = {
    id: number,
    name: string,
    addr: string,
    vaultToken: string,
    chainWeights: ChainWeight[],
    relayOutMinAmounts: RelayOutMinAmount[]
}

type VaultFeeRate = {
    ammVault: number,
    fromVault: number,
    toVault: number,
    reserved: number,
}

type BalanceFeeRate = {
    balanceThreshold: number,
    fixedFromBalance: number,
    fixedToBalance: number,
    minBalance: number,
    maxBalance: number,
    reserved: number,
}

export async function getVaultFeeRate(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "tokenRegister.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let tokenRegister: TokenRegister;
    let rawdata = fs.readFileSync(p, "utf-8");
    tokenRegister = JSON.parse(rawdata);
    return tokenRegister.vaultFeeRate;
}

export async function getBalanceFeeRate(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "tokenRegister.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let tokenRegister: TokenRegister;
    let rawdata = fs.readFileSync(p, "utf-8");
    tokenRegister = JSON.parse(rawdata);
    return tokenRegister.balanceFeeRate;
}

export async function getTokenRegisterByTokenName(network: string, tokenName: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "tokenRegister.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let tokenRegister: TokenRegister;
    let rawdata = fs.readFileSync(p, "utf-8");
    tokenRegister = JSON.parse(rawdata);
    let tokenRegisters = tokenRegister.tokens;

    for (let index = 0; index < tokenRegisters.length; index++) {
        const element = tokenRegisters[index];
        if (element.name === tokenName) {
            return element;
        }
    }
    return null;
}

export async function getAllTokenRegister(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "tokenRegister.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let tokenRegister: TokenRegister;
    let rawdata = fs.readFileSync(p, "utf-8");
    tokenRegister = JSON.parse(rawdata);
    return tokenRegister.tokens;
}

type FeeShares = {
    feeType: number,
    share: number,
    receiver: string,
}

type ProtocolFee = {
    totalRate: number
    tokens: any[],
    feeShares: FeeShares[]
}

export async function getProtocolFeeConfig(network: string) {
    let filePath = getConfigPath();
    let p = path.join(__dirname, filePath + "protocolFee.json");
    if (!fs.existsSync(p)) throw (`file ${p} not exist`);
    let protocolFee: ProtocolFee;
    let rawdata = fs.readFileSync(p, "utf-8");
    protocolFee = JSON.parse(rawdata);
    return protocolFee;
}

// Unified config path — based on NETWORK_ENV only
function getConfigPath() {
    const env = getEnv();
    if (env === "test") return "../../configs/testnet/";
    if (env === "main") return "../../configs/mainnet/";
    return "../../configs/prod/";
}

export async function verify(hre: HardhatRuntimeEnvironment, addr: string, args: any[], code: string) {
    console.log(args);
    const verifyArgs = args.map((arg) => (typeof arg == "string" ? `'${arg}'` : arg)).join(" ");
    console.log(`To verify, run: \n npx hardhat verify --network ${hre.network.name} --contract ${code} ${addr} ${verifyArgs}`);
    if (hre.network.config.chainId !== 22776) return;
    console.log(`verify ${code} ...`);
    console.log("addr:", addr);
    console.log("args:", args);
    await hre.run("verify:verify", {
        contract: code,
        address: addr,
        constructorArguments: args,
    });
}
