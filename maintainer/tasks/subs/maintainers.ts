import { task } from "hardhat/config";
import { Maintainers } from "../../typechain-types/contracts/Maintainers"
import { deployProxy, verify, saveDeployment, getDeployment } from "./utils"

task("Maintainers:deploy", "deploy Maintainers")
    .addParam("authority", "authority addresss")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let Maintainers = await ethers.getContractFactory("Maintainers");
        let m = await(await Maintainers.deploy()).waitForDeployment();
        console.log("impl address: ", await m.getAddress())
        let addr = await deployProxy(hre, await m.getAddress(), taskArgs.authority)
        console.log("Maintainers deploy to: ", addr);
        await saveDeployment(network.name, "Maintainers", addr);
        await verify(hre, await m.getAddress(), [], "contracts/Maintainers.sol:Maintainers")
});

task("Maintainers:upgrade", "upgrade Maintainers")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let Maintainers = await ethers.getContractFactory("Maintainers");
        let i = await(await Maintainers.deploy()).waitForDeployment();
        console.log("impl address: ", await i.getAddress())
        let addr = await getDeployment(network.name, "Maintainers");
        let m = await ethers.getContractAt("Maintainers", addr, deployer) as Maintainers;
        await(await m.upgradeToAndCall(await i.getAddress(), "0x")).wait();
        await verify(hre, await i.getAddress(), [], "contracts/Maintainers.sol:Maintainers")
});

task("Maintainers:set", "Maintainers set tssmanager and parameters")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Maintainers");
        let tssManager = await getDeployment(network.name, "TSSManager");
        let p = await getDeployment(network.name, "Parameters");
        let m = await ethers.getContractAt("Maintainers", addr, deployer) as Maintainers;

        await(await m.set(tssManager, p)).wait()

        console.log("tssManager:", await m.tssManager());
        console.log("parameters:", await m.parameters());
});


task("Maintainers:updateMaintainerLimit", "Maintainers set")
    .addParam("limit", "limit count")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Maintainers");
        let m = await ethers.getContractAt("Maintainers", addr, deployer) as Maintainers;

        await(await m.updateMaintainerLimit(taskArgs.limit)).wait()

        console.log("limit count:", await m.maintainerLimit());
});