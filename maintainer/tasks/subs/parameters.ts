import { task } from "hardhat/config";
import { Parameters } from "../../typechain-types/contracts/Parameters"
import { deployProxy, verify, saveDeployment, getDeployment } from "./utils";

task("Parameters:deploy", "deploy Parameters")
    .addParam("authority", "authority addresss")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let Parameters = await ethers.getContractFactory("Parameters");
        let p = await(await Parameters.deploy()).waitForDeployment();
        console.log("impl address: ", await p.getAddress())
        let addr = await deployProxy(hre, await p.getAddress(), taskArgs.authority)
        console.log("Parameters deploy to: ", addr);
        await saveDeployment(network.name, "Parameters", addr);
        await verify(hre, await p.getAddress(), [], "contracts/Parameters.sol:Parameters")
});

task("Parameters:upgrade", "upgrade Parameters")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let Parameters = await ethers.getContractFactory("Parameters");
        let i = await(await Parameters.deploy()).waitForDeployment();
        console.log("impl address: ", await i.getAddress())
        let addr = await getDeployment(network.name, "Parameters");
        let p = await ethers.getContractAt("Parameters", addr, deployer) as Parameters;
        await(await p.upgradeToAndCall(await i.getAddress(), "0x")).wait();
        await verify(hre, await i.getAddress(), [], "contracts/Parameters.sol:Parameters")
});


task("Parameters:set", "Parameters set")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Parameters");
        console.log("Parameters:", addr);
        let p = await ethers.getContractAt("Parameters", addr, deployer);
        let params = require("../../config/parameters.json")
        for(let index = 0; index < params.length; index++) {
            const element = params[index];
            console.log(element.key, element.value);
            await(await p.set(element.key, element.value)).wait();
            console.log(await p.get(element.key));
        }
});




