import { task } from "hardhat/config";
import { Relay } from "../../typechain-types/contracts"
import { getDeploymentByKey, getAllChainTokens, hasDeployment } from "../utils/utils"

task("relay:setRegistry", "set registry address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        let registry = await getDeploymentByKey(network.name, "Registry");
        let currentRegistry = await relay.registry();
        if (currentRegistry.toLowerCase() === registry.toLowerCase()) {
            console.log("registry already set to", currentRegistry, ", skipping");
            return;
        }
        console.log("on-chain registry:", currentRegistry, ", config registry:", registry, ", updating...");
        await(await relay.setRegistry(registry)).wait();
        console.log("after registry is", await relay.registry());
});


task("relay:setVaultManager", "set Vault Manager address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        let vaultManager = await getDeploymentByKey(network.name, "VaultManager");
        let currentVaultManager = await relay.vaultManager();
        if (currentVaultManager.toLowerCase() === vaultManager.toLowerCase()) {
            console.log("vaultManager already set to", currentVaultManager, ", skipping");
            return;
        }
        console.log("on-chain vaultManager:", currentVaultManager, ", config vaultManager:", vaultManager, ", updating...");
        await(await relay.setVaultManager(vaultManager)).wait();
        console.log("after vaultManager is", await relay.vaultManager());
});

task("relay:addAllChains", "add all chains")
    .addOptionalParam("dryrun", "dry run mode, only show diff (set false to execute)", "true")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const dryRun = taskArgs.dryrun === "true";
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        let chainTokens = await getAllChainTokens(network.name);
        if(!chainTokens) throw("no chain token configs");
        let keys = Object.keys(chainTokens);
        for (let index = 0; index < keys.length; index++) {
            const name = keys[index];
            if(!chainTokens[name].lastScanBlock || chainTokens[name].lastScanBlock <= 0) {
                console.log(`[skip] ${name} chainId(${chainTokens[name].chainId}) lastScanBlock is 0`);
                continue;
            }
            // Skip chains without Gateway/Relay deployment
            let contractKey = (name === network.name || name === "Mapo" || name === "Mapo_test") ? "Relay" : "Gateway";
            let deployed = await hasDeployment(name, contractKey);
            if (!deployed) {
                console.log(`[skip] ${name} chainId(${chainTokens[name].chainId}) ${contractKey} not deployed`);
                continue;
            }
            let currentBlock = await relay.getChainLastScanBlock(chainTokens[name].chainId);
            if (currentBlock > 0n) {
                console.log(`[skip] ${name} chainId(${chainTokens[name].chainId}) already added, lastScanBlock(${currentBlock})`);
                continue;
            }
            console.log(`[new]  ${name} chainId(${chainTokens[name].chainId}), lastScanBlock(${chainTokens[name].lastScanBlock})`);
            if (!dryRun) {
                await(await relay.addChain(chainTokens[name].chainId, chainTokens[name].lastScanBlock)).wait();
            }
        }
});

task("relay:addChain", "add chain")
    .addParam("chain", "chain id")
    .addParam("block", "last block")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        let currentBlock = await relay.getChainLastScanBlock(taskArgs.chain);
        if (currentBlock > 0n) {
            console.log(`chain ${taskArgs.chain} already added with lastScanBlock(${currentBlock}), skipping`);
            return;
        }
        console.log(`relay add chain chainId(${taskArgs.chain}), lastScanBlock(${taskArgs.block})`)
        await(await relay.addChain(taskArgs.chain, taskArgs.block)).wait();

});

task("relay:removeChain", "remove chain")
    .addParam("chain", "chain id")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        await(await relay.removeChain(taskArgs.chain)).wait();
});