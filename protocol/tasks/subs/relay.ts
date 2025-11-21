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
        console.log("pre registry is", await relay.registry());
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
        console.log("pre vaultManager is", await relay.vaultManager());
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
                console.log(`relay add chain chainId(${chainTokens[name].chainId}), lastScanBlock(${chainTokens[name].lastScanBlock})`)
                await relay.addChain(chainTokens[name].chainId, chainTokens[name].lastScanBlock);
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
        console.log(`relay add chain chainId(${taskArgs.chain}), lastScanBlock${taskArgs.block}`)
        await relay.addChain(taskArgs.chain, taskArgs.block);

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





