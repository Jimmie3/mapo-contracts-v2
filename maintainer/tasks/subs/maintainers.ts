import { task, types } from "hardhat/config";
import { Maintainers } from "../../typechain-types/contracts/Maintainers"
import { saveDeployment, getDeployment } from "./utils"

task("Maintainers:deploy", "deploy Maintainers")
    .addParam("authority", "authority addresss")
    .addParam("verify", "verify impl after deploy (true/false)", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        const { createDeployer } = require("@mapprotocol/common-contracts/utils/deployer");
        const deployer = createDeployer(hre, { autoVerify: taskArgs.verify === "true" });
        let result = await deployer.deployProxy("Maintainers", [taskArgs.authority]);
        console.log("Maintainers proxy:", result.proxy);
        console.log("Maintainers impl:", result.implementation);
        await saveDeployment(network.name, "Maintainers", result.proxy);
});

task("Maintainers:set", "Maintainers set tssmanager and parameters")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [signer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Maintainers");
        let tssManager = await getDeployment(network.name, "TSSManager");
        let p = await getDeployment(network.name, "Parameters");
        let m = await ethers.getContractAt("Maintainers", addr, signer) as Maintainers;

        await(await m.set(tssManager, p)).wait()

        console.log("tssManager:", await m.tssManager());
        console.log("parameters:", await m.parameters());
});


task("Maintainers:updateMaintainerLimit", "Maintainers set")
    .addParam("limit", "limit count")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [signer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Maintainers");
        let m = await ethers.getContractAt("Maintainers", addr, signer) as Maintainers;

        await(await m.updateMaintainerLimit(taskArgs.limit)).wait()

        console.log("limit count:", await m.maintainerLimit());
});
