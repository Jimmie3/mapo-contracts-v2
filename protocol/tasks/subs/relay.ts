import { task } from "hardhat/config";
import { Relay } from "../../typechain-types/contracts"
import { getDeploymentByKey, getAllChainTokens } from "../utils/utils"

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

task("relay:addAllChain", "add Chain")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
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
            if(chainTokens[name].lastScanBlock && chainTokens[name].lastScanBlock > 0) {
                let currentBlock = await relay.getChainLastScanBlock(chainTokens[name].chainId);
                if (currentBlock > 0n) {
                    console.log(`chain ${chainTokens[name].chainId} already added with lastScanBlock(${currentBlock}), skipping`);
                    // continue;
                }
                console.log(`relay add chain chainId(${chainTokens[name].chainId}), lastScanBlock(${chainTokens[name].lastScanBlock})`)
                await(await relay.addChain(chainTokens[name].chainId, chainTokens[name].lastScanBlock)).wait();
            }
        }
});

task("relay:addChain", "add Chain")
    .addParam("chain")
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

task("relay:removeChain", "remove Chain")
    .addParam("chain")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        await(await relay.removeChain(taskArgs.chain)).wait();
});





