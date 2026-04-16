import { isTronNetwork } from "./tronHelper";

// TronScan API endpoints
const TRONSCAN_API: Record<string, string> = {
    "Tron": "https://apilist.tronscan.org/api/solidity/contract/verify",
    "tron_test": "https://nile.tronscan.org/api/solidity/contract/verify",
    "Tron_test": "https://nile.tronscan.org/api/solidity/contract/verify",
};

export interface VerifyOptions {
    address: string;          // contract address
    contractName: string;     // e.g. "AuthorityManager"
    contractPath?: string;    // e.g. "contracts/AuthorityManager.sol:AuthorityManager"
    constructorArgs?: any[];  // constructor arguments
    compiler?: string;        // solc version, defaults to "0.8.25"
    optimizer?: boolean;      // defaults to true
    optimizerRuns?: number;   // defaults to 200
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
    const apiUrl = TRONSCAN_API[network];
    if (!apiUrl) {
        console.log(`no TronScan API for network ${network}, skipping verification`);
        return;
    }

    const compiler = opts.compiler || "0.8.25";
    const optimizer = opts.optimizer !== false;
    const optimizerRuns = opts.optimizerRuns || 200;

    // Generate flattened source
    console.log(`flattening ${opts.contractName} for TronScan verification...`);
    let flattenedSource: string;
    try {
        flattenedSource = await hre.run("flatten:get-flattened-sources", {
            files: [`contracts/${opts.contractName}.sol`],
        });
        // Remove duplicate SPDX license identifiers (flatten creates duplicates)
        flattenedSource = removeDuplicateSPDX(flattenedSource);
    } catch (e) {
        // Fallback: try reading from verify-output if flatten fails
        const fs = require("fs");
        const path = require("path");
        const flattenPath = path.join(process.cwd(), `verify-output/${opts.contractName}_flatten.sol`);
        if (fs.existsSync(flattenPath)) {
            flattenedSource = fs.readFileSync(flattenPath, "utf-8");
            console.log(`using cached flatten from ${flattenPath}`);
        } else {
            console.log(`flatten failed, generate manually: forge flatten contracts/${opts.contractName}.sol`);
            return;
        }
    }

    // Convert address to Tron format if needed
    let address = opts.address;
    if (address.startsWith("0x")) {
        const { tronFromHex } = require("./tronHelper");
        address = tronFromHex(address);
    }

    const payload = {
        contractAddress: address,
        contractName: opts.contractName,
        compilerVersion: `v${compiler}`,
        sourceCode: flattenedSource,
        optimization: optimizer,
        optimizerRuns: optimizerRuns,
    };

    console.log(`submitting verification to TronScan for ${address}...`);

    try {
        const response = await fetch(apiUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
        });

        const result = await response.json();

        if (response.ok && (result.code === 0 || result.success)) {
            console.log(`${opts.contractName} verified on TronScan`);
        } else {
            console.log(`TronScan verification response:`, JSON.stringify(result, null, 2));
            console.log(`if failed, verify manually at https://${network === "Tron" ? "" : "nile."}tronscan.org/#/contract/${address}/code`);
        }
    } catch (e: any) {
        console.log(`TronScan API error: ${e.message || e}`);
        console.log(`verify manually at https://${network === "Tron" ? "" : "nile."}tronscan.org/#/contract/${address}/code`);
    }
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
