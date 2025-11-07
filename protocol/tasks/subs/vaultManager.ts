import { task } from "hardhat/config";
import { VaultManager } from "../../typechain-types/contracts"
import { getDeploymentByKey, getVaultFeeRate, getTokenRegsterByTokenName, getAllTokenRegster } from "./utils"

task("vaultManager:updateVaultFeeRate", "update Vault Fee Rate")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let vaultFeeRate = await getVaultFeeRate(network.name);
        console.log(`pre vaultFeeRate === `, await vaultManager.vaultFeeRate())
        await(await vaultManager.updateVaultFeeRate(vaultFeeRate)).wait()
        console.log(`after vaultFeeRate === `, await vaultManager.vaultFeeRate())
});

task("vaultManager:setRelay", "set Relay address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let relay = await getDeploymentByKey(network.name, "Relay");

        console.log(`pre relay === `, await vaultManager.relay())
        await(await vaultManager.setRelay(relay)).wait()
        console.log(`after relay === `, await vaultManager.relay())
});

task("vaultManager:setPeriphery", "set Periphery address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let periphery = await getDeploymentByKey(network.name, "Periphery");

        console.log(`pre periphery === `, await vaultManager.periphery())
        await(await vaultManager.setPeriphery(periphery)).wait()
        console.log(`after periphery === `, await vaultManager.periphery())
});

task("vaultManager:updateTokenWeights", "update Token Weights by token name")
    .addParam("token", "token name")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegister = await getTokenRegsterByTokenName(network.name, taskArgs.token);
        if(!tokenRegister) throw("token not exsit");
        if(!tokenRegister.chainWeights || tokenRegister.chainWeights.length === 0) throw("not chainWeights");

        let chains = tokenRegister.chainWeights.map(item => item.chainId);
        let weights = tokenRegister.chainWeights.map(item => item.weight);
        console.log(`token ${taskArgs.token} updateTokenWeights chains(${chains}), weights(${weights})`);
        await(await vaultManager.updateTokenWeights(tokenRegister.addr, chains, weights)).wait()
});

task("vaultManager:updateAllTokenWeights", "update Token Weights")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegisters = await getAllTokenRegster(network.name);
        if(!tokenRegisters || tokenRegisters.length === 0 ) throw("no token to register");
        for (let index = 0; index < tokenRegisters.length; index++) {
            const element = tokenRegisters[index];
            let chains = element.chainWeights.map(item => item.chainId);
            let weights = element.chainWeights.map(item => item.weight);
            console.log(`token ${element.name} updateTokenWeights chains(${chains}), weights(${weights})`);
            await(await vaultManager.updateTokenWeights(element.addr, chains, weights)).wait()
        }
});

task("vaultManager:registerToken", "register Token")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegisters = await getAllTokenRegster(network.name);
        if(!tokenRegisters || tokenRegisters.length === 0 ) throw("no token to register");

        for (let index = 0; index < tokenRegisters.length; index++) {
            const element = tokenRegisters[index];
            if(element.vaultToken.length > 0) {
               console.log(`registerToken ${element.name} token(${element.addr}), vault(${element.vaultToken})`);
               await(await vaultManager.registerToken(element.addr, element.vaultToken)).wait();
            }
        }

});



