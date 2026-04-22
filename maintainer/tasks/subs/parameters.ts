import { task, types } from "hardhat/config";
import { saveDeployment, getDeployment } from "./utils";

task("Parameters:deploy", "deploy Parameters")
    .addParam("authority", "authority addresss")
    .addParam("verify", "verify impl after deploy (true/false)", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        const { createDeployer } = require("@mapprotocol/common-contracts/utils/deployer");
        const deployer = createDeployer(hre, { autoVerify: taskArgs.verify === "true" });
        let result = await deployer.deployProxy("Parameters", [taskArgs.authority]);
        console.log("Parameters proxy:", result.proxy);
        console.log("Parameters impl:", result.implementation);
        await saveDeployment(network.name, "Parameters", result.proxy);
});

task("Parameters:set", "Parameters set")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [signer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Parameters");
        console.log("Parameters:", addr);
        let p = await ethers.getContractAt("Parameters", addr, signer);
        let params = require("../../config/parameters.json")
        for(let index = 0; index < params.length; index++) {
            const element = params[index];
            console.log(element.key, element.value);
            await(await p.set(element.key, element.value)).wait();
            console.log(await p.get(element.key));
        }
});
