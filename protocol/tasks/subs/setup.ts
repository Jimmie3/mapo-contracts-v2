import { task } from "hardhat/config";
import { getAllChainTokens, getDeploymentByKey } from "../utils/utils"

// Full initialization after deployment (steps 3-16 from index.ts)
task("setup:init", "initialize all contracts after deployment")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const dryrun = taskArgs.dryrun;
        console.log(`\n===== setup:init (dryrun: ${dryrun}) =====\n`);

        const steps = [
            { name: "gateway:updateTokens", args: { dryrun } },
            { name: "gateway:setTransferFailedReceiver", args: {} },
            { name: "gateway:updateMinGasCallOnReceive", args: {} },
            { name: "vaultManager:updateVaultFeeRate", args: {} },
            { name: "vaultManager:updateBalanceFeeRate", args: {} },
            { name: "vaultManager:registerToken", args: { dryrun } },
            { name: "registry:registerAllChains", args: { dryrun } },
            { name: "registry:registerAllTokens", args: { dryrun } },
            { name: "registry:mapAllTokens", args: { dryrun } },
            { name: "registry:setAllTokenTicker", args: { dryrun } },
            { name: "relay:addAllChains", args: { dryrun } },
            { name: "vaultManager:updateAllTokenWeights", args: { dryrun } },
            { name: "vaultManager:setAllMinAmount", args: { dryrun } },
        ];

        for (const step of steps) {
            console.log(`\n----- ${step.name} -----`);
            try {
                await hre.run(step.name, step.args);
            } catch (e: any) {
                console.log(`[warn] ${step.name} failed: ${e.message || e}`);
            }
        }

        console.log(`\n===== setup:init done =====\n`);
});

// Add a single chain: registerChain -> mapTokens for that chain -> setTickers -> relay addChain
task("setup:addChain", "add a new chain with all config steps")
    .addParam("chain", "chain name (e.g., Bsc, Eth, Base)")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const { chain } = taskArgs;
        const dryrun = taskArgs.dryrun;
        console.log(`\n===== setup:addChain ${chain} (dryrun: ${dryrun}) =====\n`);

        // 1. Register the chain in Registry
        console.log(`\n----- registry:registerChain -----`);
        try {
            await hre.run("registry:registerChain", { name: chain });
        } catch (e: any) {
            console.log(`[warn] registry:registerChain failed: ${e.message || e}`);
        }

        // 2. Map tokens for this chain only
        console.log(`\n----- registry:mapTokenByChain (${chain}) -----`);
        let chainTokens = await getAllChainTokens(network.name);
        if (chainTokens && chainTokens[chain]) {
            let chainConfig = chainTokens[chain];
            let tokens = chainConfig.tokens;
            if (tokens && tokens.length > 0) {
                for (const token of tokens) {
                    try {
                        await hre.run("registry:mapTokenByName", {
                            token: token.name,
                            dryrun
                        });
                    } catch (e: any) {
                        console.log(`[warn] mapTokenByName ${token.name} failed: ${e.message || e}`);
                    }
                }
            }
        }

        // 3. Set token tickers for this chain
        console.log(`\n----- registry:setTokenTickerByChain -----`);
        try {
            await hre.run("registry:setTokenTickerByChain", { chain, dryrun });
        } catch (e: any) {
            console.log(`[warn] setTokenTickerByChain failed: ${e.message || e}`);
        }

        // 4. Add chain to relay
        console.log(`\n----- relay:addChain -----`);
        if (chainTokens && chainTokens[chain]) {
            let chainConfig = chainTokens[chain];
            if (chainConfig.lastScanBlock && chainConfig.lastScanBlock > 0) {
                try {
                    await hre.run("relay:addChain", {
                        chain: String(chainConfig.chainId),
                        block: String(chainConfig.lastScanBlock)
                    });
                } catch (e: any) {
                    console.log(`[warn] relay:addChain failed: ${e.message || e}`);
                }
            } else {
                console.log(`[skip] ${chain} lastScanBlock is 0`);
            }
        }

        console.log(`\n===== setup:addChain ${chain} done =====\n`);
});