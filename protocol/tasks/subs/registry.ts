import { task } from "hardhat/config";
import { Registry } from "../../typechain-types/contracts"
import {
    getDeploymentByKey,
    getAllChainTokens,
    getChainTokenByNetwork,
    getTokenRegisterByTokenName,
    getAllTokenRegister
} from "../utils/utils"
import { addressToHex } from "../utils/addressUtil"

task("registry:registerAllChains", "register all chain info")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;

        let chainTokens = await getAllChainTokens(network.name);
        if(!chainTokens) throw("no chain token configs");
        let keys = Object.keys(chainTokens);
        for (let index = 0; index < keys.length; index++) {
            const name = keys[index];
            await registerChain(name, registry, chainTokens[name], dryRun);
        }

});

task("registry:registerChain", "register chain info by network name")
    .addParam("name", "chain name")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;

        let chainToken = await getChainTokenByNetwork(taskArgs.name);
        if(!chainToken) throw("chain info not set");
        await registerChain(taskArgs.name, registry, chainToken)
});

task("registry:deregisterChain", "deregisterChain")
    .addParam("chain", "chain id")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        console.log(`removeChain chain(${taskArgs.chain})`);
        await(await registry.deregisterChain(taskArgs.chain)).wait();
});

task("registry:registerToken", "register token by token name")
    .addParam("name", "token name")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        let token = await getTokenRegisterByTokenName(network.name, taskArgs.name);
        if(!token || token === null) throw("token not set");
        // Check if token is already registered with same address
        let existingToken = await registry.getTokenAddressById(token.id);
        if (existingToken.toLowerCase() === token.addr.toLowerCase()) {
            console.log(`token ${token.name} id(${token.id}) already registered with same address, skipping`);
            return;
        }
        if (existingToken !== "0x0000000000000000000000000000000000000000") {
            console.log(`token ${token.name} id(${token.id}) on-chain address: ${existingToken}, config address: ${token.addr}, updating...`);
        }
        console.log(`registerToken ${token.name} id(${token.id}), addr(${token.addr}, vaultToken(${token.vaultToken}))`);
        await(await registry.registerToken(token.id, token.addr)).wait();
});

task("registry:registerAllTokens", "register all tokens")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        let tokens = await getAllTokenRegister(network.name);
        if(!tokens || tokens.length === 0) throw("token not set");
        for (let index = 0; index < tokens.length; index++) {
            const token = tokens[index];
            let existingToken = await registry.getTokenAddressById(token.id);
            if (existingToken.toLowerCase() === token.addr.toLowerCase()) {
                console.log(`[skip] token ${token.name} id(${token.id}) already registered`);
                continue;
            }
            if (existingToken !== "0x0000000000000000000000000000000000000000") {
                console.log(`[diff] token ${token.name} id(${token.id}) on-chain: ${existingToken} -> config: ${token.addr}`);
            } else {
                console.log(`[new]  token ${token.name} id(${token.id}), addr(${token.addr})`);
            }
            if (!dryRun) {
                await(await registry.registerToken(token.id, token.addr)).wait();
            }
        }
});



task("registry:setTokenTicker", "set token ticker")
    .addParam("chain", "chain id")
    .addParam("addr", "token address (supports EVM, Tron, Solana formats)")
    .addParam("name", "token nickname")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        const tokenAddrBytes = addressToHex(taskArgs.addr);
        console.log(`set Token Ticker chain(${taskArgs.chain}), addr(${taskArgs.addr} -> ${tokenAddrBytes}), name(${taskArgs.name})`);
        await(await registry.setTokenTicker(taskArgs.chain, tokenAddrBytes, taskArgs.name)).wait();
});

task("registry:setTokenTickerByChain", "set token tickers by chain name")
    .addParam("chain", "chain name")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        let chainTokens = await getAllChainTokens(network.name);
        if(!chainTokens) throw("no chain token configs");
        let keys = Object.keys(chainTokens);
        for (let index = 0; index < keys.length; index++) {
            if(taskArgs.chain !== keys[index]) continue;
            const name = keys[index];
            let element = chainTokens[name]
            let tokens = element.tokens;
            if(!tokens || tokens.length === 0) continue;
            for (let j = 0; j < tokens.length; j++) {
                const token = tokens[j];
                const tokenAddrBytes = addressToHex(token.addr);
                let preTicker = await registry.getTokenNickname(element.chainId, tokenAddrBytes);
                if(preTicker === token.name) {
                    console.log(`[skip] ${token.name} on chain(${element.chainId}) ticker already set`);
                    continue;
                }
                console.log(`[diff] ${token.name} on chain(${element.chainId}): "${preTicker}" -> "${token.name}"`);
                if (!dryRun) {
                    await(await registry.setTokenTicker(element.chainId, tokenAddrBytes, token.name)).wait();
                }
            }
        }
});

task("registry:setAllTokenTicker", "set all token tickers")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        let chainTokens = await getAllChainTokens(network.name);
        if(!chainTokens) throw("no chain token configs");
        let keys = Object.keys(chainTokens);
        for (let index = 0; index < keys.length; index++) {
            const name = keys[index];
            let element = chainTokens[name]
            let tokens = element.tokens;
            if(!tokens || tokens.length === 0) continue;
            for (let j = 0; j < tokens.length; j++) {
                const token = tokens[j];
                const tokenAddrBytes = addressToHex(token.addr);
                let preTicker = await registry.getTokenNickname(element.chainId, tokenAddrBytes);
                if(preTicker === token.name) {
                    console.log(`[skip] ${token.name} on chain(${element.chainId}) ticker already set`);
                    continue;
                }
                console.log(`[diff] ${token.name} on chain(${element.chainId}): "${preTicker}" -> "${token.name}"`);
                if (!dryRun) {
                    await(await registry.setTokenTicker(element.chainId, tokenAddrBytes, token.name)).wait();
                }
            }
        }
});


task("registry:unmapToken", "unmap Token")
    .addParam("chain", "chain id")
    .addParam("addr", "token address (supports EVM, Tron, Solana formats)")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        const tokenAddrBytes = addressToHex(taskArgs.addr);
        console.log(`unmap Token: chain(${taskArgs.chain}),  addr(${taskArgs.addr} -> ${tokenAddrBytes})`);
        await(await registry.unmapToken(taskArgs.chain, tokenAddrBytes)).wait();
});

task("registry:mapAllTokens", "map all tokens")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        let tokens = await getAllTokenRegister(network.name);
        if(!tokens || tokens.length === 0) throw("token not set");
        for (let index = 0; index < tokens.length; index++) {
            const token = tokens[index];
            await hre.run("registry:mapTokenByName", {
                token: token.name,
                dryrun: dryRun ? "true" : "false"
            })
        }
});

task("registry:mapTokenByName", "map token by token name")
    .addParam("token", "token name")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;

        let relayToken = await getTokenRegisterByTokenName(network.name, taskArgs.token);
        if(!relayToken) throw("token not set");

        let chainTokens = await getAllChainTokens(network.name);
        if(!chainTokens) throw("no chain token configs");
        let keys = Object.keys(chainTokens);

        for (let index = 0; index < keys.length; index++) {
            let key = keys[index]
            if(key === network.name) continue;
            let element = chainTokens[key]
            const tokens = element.tokens;
            if(!tokens || tokens.length === 0) continue;
            for (let j = 0; j < tokens.length; j++) {
                const token = tokens[j];
                if(token.name === taskArgs.token) {
                    const tokenAddrBytes = addressToHex(token.addr);
                    let existingMapping = await registry.getToChainToken(relayToken.addr, element.chainId);
                    let existingDecimals = await registry.getTokenDecimals(element.chainId, tokenAddrBytes);
                    let existingMappingHex = existingMapping.toLowerCase();
                    if (existingMappingHex === tokenAddrBytes.toLowerCase() && Number(existingDecimals) === token.decimals) {
                        console.log(`[skip] ${token.name} on chain(${element.chainId}) already mapped`);
                        continue;
                    }
                    if (existingMapping && existingMapping !== "0x") {
                        console.log(`[diff] ${token.name} on chain(${element.chainId}): ${existingMapping}(${existingDecimals}) -> ${tokenAddrBytes}(${token.decimals})`);
                    } else {
                        console.log(`[new]  ${token.name} on chain(${element.chainId}): ${token.addr} -> ${tokenAddrBytes}, decimals(${token.decimals})`);
                    }
                    if (!dryRun) {
                        await(await registry.mapToken(relayToken.addr, element.chainId, tokenAddrBytes, token.decimals)).wait();
                    }
                }
            }
        }

});

task("registry:mapToken", "map Token")
    .addParam("token", "relay chain token address")
    .addParam("chain", "from chain id")
    .addParam("addr", "from token address (supports EVM, Tron, Solana formats)")
    .addParam("decimals", "from token decimals")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RegistryFactory = await ethers.getContractFactory("Registry");
        let addr = await getDeploymentByKey(network.name, "Registry");
        const registry = RegistryFactory.attach(addr) as Registry;
        const tokenAddrBytes = addressToHex(taskArgs.addr);
        let existingMapping = await registry.getToChainToken(taskArgs.token, taskArgs.chain);
        let existingDecimals = await registry.getTokenDecimals(taskArgs.chain, tokenAddrBytes);
        if (existingMapping.toLowerCase() === tokenAddrBytes.toLowerCase() && Number(existingDecimals) === Number(taskArgs.decimals)) {
            console.log(`token on chain(${taskArgs.chain}) already mapped with same values, skipping`);
            return;
        }
        if (existingMapping && existingMapping !== "0x") {
            console.log(`on-chain mapping: ${existingMapping}, decimals: ${existingDecimals}`);
            console.log(`config mapping: ${taskArgs.addr} -> ${tokenAddrBytes}, decimals: ${taskArgs.decimals}, updating...`);
        }
        console.log(`map token ${taskArgs.token}, chain(${taskArgs.chain}), addr(${taskArgs.addr} -> ${tokenAddrBytes}), decimals(${taskArgs.decimals})`);
        await(await registry.mapToken(taskArgs.token, taskArgs.chain, tokenAddrBytes, taskArgs.decimals)).wait();
});


async function registerChain(network: string, registry: Registry, chainToken: {
        chainId: number,
        lastScanBlock: number,
        chainType: string,
        gasToken: string,
        baseFeeToken:string,
        tokens: any[]}, dryRun: boolean = false) {

        let chainType = (chainToken.chainType === "contract") ? 0 : 1;

        let isRegistered = await registry.isRegistered(chainToken.chainId);
        if (isRegistered) {
            console.log(`[skip] chain ${chainToken.chainId} (${network}) already registered`);
            return;
        }

        let router = await getRouter(network);
        console.log(
            `[new]  registerChain ${network} chain(${chainToken.chainId}), chainType(${chainType}), router(${router}), gasToken(${chainToken.gasToken}), baseFeeToken(${chainToken.baseFeeToken})`
        );
        if (!dryRun) {
            await(await registry.registerChain(
                chainToken.chainId,
                chainType,
                router,
                chainToken.gasToken,
                chainToken.baseFeeToken,
                network
            )).wait()
        }
}

async function getRouter(network:string) {
        let router;
        if(network === "Mapo_test" || network === "Mapo") {
            router = await getDeploymentByKey(network, "Relay");
        } else {
            try {
                router = await getDeploymentByKey(network, "Gateway");
            } catch (error) {
                router = "0x";
            }
        }
        return router;
}