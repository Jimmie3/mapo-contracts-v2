/**
 * Contract verification — supports Etherscan, Blockscout (Mapo), and TronScan.
 * Auto-routes based on network name.
 */
import { isTronNetwork, tronFromHex } from "./tronHelper";

// TronScan API endpoints by chainId
const TRONSCAN_API: Record<number, string> = {
    728126428: "https://apilist.tronscan.org/api/solidity/contract/verify",   // mainnet
    3448148188: "https://nile.tronscan.org/api/solidity/contract/verify",     // nile testnet
};

export interface VerifyOptions {
    address: string;             // contract address
    contractName: string;        // e.g. "AuthorityManager"
    contractPath?: string;       // e.g. "contracts/AuthorityManager.sol:AuthorityManager"
    constructorArgs?: any[];     // constructor arguments (raw values)
    constructorParams?: string;  // pre-encoded constructor params hex (without 0x), overrides constructorArgs
    compiler?: string;           // solc version, defaults to "0.8.25"
    optimizer?: boolean;         // defaults to true
    optimizerRuns?: number;      // defaults to 200
}

/**
 * Unified contract verification — auto-routes to EVM (hardhat verify) or Tron (TronScan API)
 */
export async function verify(hre: any, opts: VerifyOptions): Promise<void> {
    const network = hre.network.name;

    if (isTronNetwork(network)) {
        await verifyTron(hre, network, opts);
    } else {
        await verifyEvm(hre, opts);
    }
}

// ============================================================
// EVM verification via hardhat-verify
// ============================================================

async function verifyEvm(hre: any, opts: VerifyOptions): Promise<void> {
    const contractPath = opts.contractPath || `contracts/${opts.contractName}.sol:${opts.contractName}`;

    console.log(`verifying ${opts.contractName} at ${opts.address} ...`);

    try {
        await hre.run("verify:verify", {
            contract: contractPath,
            address: opts.address,
            constructorArguments: opts.constructorArgs || [],
        });
        console.log(`${opts.contractName} verified`);
    } catch (e: any) {
        if (e.message?.includes("Already Verified")) {
            console.log(`${opts.contractName} already verified`);
        } else {
            console.log(`verification failed: ${e.message || e}`);
            // Print manual command as fallback
            const args = (opts.constructorArgs || []).map((a: any) => typeof a === "string" ? `'${a}'` : a).join(" ");
            console.log(`manual: npx hardhat verify --network ${hre.network.name} --contract ${contractPath} ${opts.address} ${args}`);
        }
    }
}

// ============================================================
// Tron verification via TronScan API
// ============================================================

async function verifyTron(hre: any, network: string, opts: VerifyOptions): Promise<void> {
    const chainId = hre.network.config.chainId;
    const fs = require("fs");
    const path = require("path");

    // Auto-read compiler settings from hardhat config
    const solcConfig = hre.config?.solidity?.compilers?.[0] || hre.config?.solidity || {};
    const compiler = opts.compiler || solcConfig.version || "0.8.25";
    const optimizer = opts.optimizer ?? solcConfig.settings?.optimizer?.enabled ?? true;
    const optimizerRuns = opts.optimizerRuns ?? solcConfig.settings?.optimizer?.runs ?? 200;
    const evmVersion = solcConfig.settings?.evmVersion || "london";
    const viaIR = solcConfig.settings?.viaIR ? "1" : "0";

    // Convert address to Tron format
    let address = opts.address;
    if (address.startsWith("0x")) {
        address = tronFromHex(address);
    }

    // Generate flattened source
    const outputDir = path.join(process.cwd(), "verify-output");
    const flattenPath = path.join(outputDir, `${opts.contractName}_flatten.sol`);

    console.log(`generating flatten for ${opts.contractName}...`);
    try {
        // Find actual source path from artifact
        const artifact = await hre.artifacts.readArtifact(opts.contractName);
        const sourcePath = artifact.sourceName; // e.g. "contracts/factory/Create2Factory.sol"
        let flattenedSource = await hre.run("flatten:get-flattened-sources", {
            files: [sourcePath],
        });
        flattenedSource = removeDuplicateSPDX(flattenedSource);
        fs.mkdirSync(outputDir, { recursive: true });
        fs.writeFileSync(flattenPath, flattenedSource);
        console.log(`flatten saved to: ${flattenPath}`);
    } catch (e) {
        if (fs.existsSync(flattenPath)) {
            console.log(`using existing flatten: ${flattenPath}`);
        } else {
            console.log(`flatten failed, generate manually: forge flatten contracts/${opts.contractName}.sol`);
            return;
        }
    }

    // Submit to TronScan API
    const apiUrl = TRONSCAN_API[chainId];
    if (!apiUrl) {
        console.log(`no TronScan API for chainId ${chainId}, printing manual instructions instead`);
        printTronVerifyInfo(address, opts.contractName, compiler, optimizer, optimizerRuns, evmVersion, flattenPath, chainId);
        return;
    }

    console.log(`submitting verification to TronScan for ${address}...`);
    try {
        const FormData = require("form-data");
        const form = new FormData();
        form.append("contractAddress", address);
        form.append("contractName", opts.contractName);
        // Read full compiler version from build-info (includes commit hash)
        let fullCompiler = `v${compiler}`;
        try {
            const buildInfoDir = path.join(process.cwd(), "artifacts/build-info");
            const buildInfoFiles = fs.readdirSync(buildInfoDir);
            if (buildInfoFiles.length > 0) {
                const buildInfo = JSON.parse(fs.readFileSync(
                    path.join(buildInfoDir, buildInfoFiles[0]), "utf-8"
                ));
                if (buildInfo.solcLongVersion) {
                    fullCompiler = `v${buildInfo.solcLongVersion}`;
                }
            }
        } catch (e: any) {
            console.log(`[warn] could not read build-info: ${e.message}`);
        }
        form.append("compiler", fullCompiler);
        form.append("license", "3"); // MIT
        form.append("optimizer", optimizer ? "1" : "0");
        form.append("runs", String(optimizerRuns));
        form.append("viaIR", viaIR);
        form.append("evmVersion", evmVersion);
        // Encode constructor params from ABI if not pre-encoded
        let constructorParams = opts.constructorParams || "";
        if (!constructorParams && opts.constructorArgs && opts.constructorArgs.length > 0) {
            const { Interface } = require("ethers");
            const artifact = await hre.artifacts.readArtifact(opts.contractName);
            const iface = new Interface(artifact.abi);
            const encoded = iface.encodeDeploy(opts.constructorArgs);
            constructorParams = encoded.slice(2); // remove 0x
        }
        form.append("constructorParams", constructorParams);
        form.append("files", fs.createReadStream(flattenPath), {
            filename: `${opts.contractName}.flat.tron.sol`,
            contentType: "application/octet-stream",
        });

        const result: any = await new Promise((resolve, reject) => {
            const url = new URL(apiUrl);
            const https = require("https");
            const req = https.request({
                hostname: url.hostname,
                path: url.pathname,
                method: "POST",
                headers: form.getHeaders(),
            }, (res: any) => {
                let data = "";
                res.on("data", (chunk: string) => data += chunk);
                res.on("end", () => {
                    try { resolve(JSON.parse(data)); } catch { resolve({ code: -1, errmsg: data }); }
                });
            });
            req.on("error", reject);
            form.pipe(req);
        });

        if (result.code === 200 || result.success) {
            console.log(`${opts.contractName} verified on TronScan: ${result.data?.message || "success"}`);
        } else {
            console.log(`TronScan response:`, JSON.stringify(result, null, 2));
            printTronVerifyInfo(address, opts.contractName, fullCompiler, optimizer, optimizerRuns, evmVersion, flattenPath, chainId);
        }
    } catch (e: any) {
        console.log(`TronScan API error: ${e.message || e}`);
        printTronVerifyInfo(address, opts.contractName, `v${compiler}`, optimizer, optimizerRuns, evmVersion, flattenPath, chainId);
    }
}

function printTronVerifyInfo(
    address: string, contractName: string, compiler: string,
    optimizer: boolean, runs: number, evmVersion: string,
    flattenPath: string, chainId: number
) {
    const isMainnet = chainId === 728126428;
    const tronscanUrl = isMainnet
        ? `https://tronscan.org/#/contract/${address}/code`
        : `https://nile.tronscan.org/#/contract/${address}/code`;

    console.log(`\n=== Verify manually on TronScan ===`);
    console.log(`Address:    ${address}`);
    console.log(`Contract:   ${contractName}`);
    console.log(`Compiler:   ${compiler}`);
    console.log(`Optimizer:  ${optimizer ? "enabled" : "disabled"}, runs: ${runs}`);
    console.log(`EVM:        ${evmVersion}`);
    console.log(`Flatten:    ${flattenPath}`);
    console.log(`URL:        ${tronscanUrl}`);
    console.log(`=====================================\n`);
}

function removeDuplicateSPDX(source: string): string {
    let found = false;
    return source.split("\n").filter(line => {
        if (line.includes("SPDX-License-Identifier")) {
            if (found) return false;
            found = true;
        }
        return true;
    }).join("\n");
}
