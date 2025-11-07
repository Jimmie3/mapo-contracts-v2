import { task } from "hardhat/config";
import { Relay } from "../../typechain-types/contracts"
import { getDeploymentByKey } from "./utils"

task("relay:setPeriphery", "set Periphery address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const RelayFactory = await ethers.getContractFactory("Relay");
        let addr = await getDeploymentByKey(network.name, "Relay");
        const relay = RelayFactory.attach(addr) as Relay;
        let periphery = await getDeploymentByKey(network.name, "Periphery");
        console.log("pre periphery is", await relay.periphery());
        await(await relay.setPeriphery(periphery)).wait();
        console.log("after periphery is", await relay.periphery());
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





