import { task } from "hardhat/config";
import { TSSManager } from "../../typechain-types/contracts/TSSManager"
import { deployProxy, verify, saveDeployment, getDeployment } from "./utils"

task("TSSManager:deploy", "deploy TSSManager")
    .addParam("authority", "authority addresss")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let TSSManager = await ethers.getContractFactory("TSSManager");
        let t = await(await TSSManager.deploy()).waitForDeployment();
        console.log("impl address: ", await t.getAddress())
        let addr = await deployProxy(hre, await t.getAddress(), taskArgs.authority)
        console.log("TSSManager deploy to: ", addr);
        await saveDeployment(network.name, "TSSManager", addr);
        await verify(hre, await t.getAddress(), [], "contracts/TSSManager.sol:TSSManager")
});


task("TSSManager:upgrade", "upgrade TSSManager")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let TSSManager = await ethers.getContractFactory("TSSManager");
        let i = await(await TSSManager.deploy()).waitForDeployment();
        console.log("impl address: ", await i.getAddress())
        let addr = await getDeployment(network.name, "TSSManager");
        let t = await ethers.getContractAt("TSSManager", addr, deployer) as TSSManager;
        await(await t.upgradeToAndCall(await i.getAddress(), "0x")).wait();
        await verify(hre, await t.getAddress(), [], "contracts/TSSManager.sol:TSSManager")
});


task("TSSManager:set", "TSSManager set")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "TSSManager");
        let maitainer = await getDeployment(network.name, "Maintainers");
        let p = await getDeployment(network.name, "Parameters");
        let relay = await getDeployment(network.name, "Relay");
        let t = await ethers.getContractAt("TSSManager", addr, deployer) as TSSManager;

        await(await t.set(maitainer, relay, p)).wait()

        console.log("relay:", await t.relay());
        console.log("parameters:", await t.parameters());
        console.log("maintainerManager:", await t.maintainerManager());
});