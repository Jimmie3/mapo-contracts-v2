import { task, types } from "hardhat/config";
import { TSSManager } from "../../typechain-types/contracts/TSSManager"
import { saveDeployment, getDeployment } from "./utils"

task("TSSManager:deploy", "deploy TSSManager")
    .addParam("authority", "authority addresss")
    .addParam("verify", "verify impl after deploy (true/false)", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        const { createDeployer } = require("@mapprotocol/common-contracts/utils/deployer");
        const deployer = createDeployer(hre, { autoVerify: taskArgs.verify === "true" });
        let result = await deployer.deployProxy("TSSManager", [taskArgs.authority]);
        console.log("TSSManager proxy:", result.proxy);
        console.log("TSSManager impl:", result.implementation);
        await saveDeployment(network.name, "TSSManager", result.proxy);
});

task("TSSManager:set", "TSSManager set")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [signer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "TSSManager");
        let maintainer = await getDeployment(network.name, "Maintainers");
        let p = await getDeployment(network.name, "Parameters");
        let relay = await getDeployment(network.name, "Relay");
        let t = await ethers.getContractAt("TSSManager", addr, signer) as TSSManager;

        await(await t.set(maintainer, relay, p)).wait()

        console.log("relay:", await t.relay());
        console.log("parameters:", await t.parameters());
        console.log("maintainerManager:", await t.maintainerManager());
});
