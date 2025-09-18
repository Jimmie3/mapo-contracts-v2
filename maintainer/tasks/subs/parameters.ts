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
        await verify(hre, await p.getAddress(), [], "contracts/Parameters.sol:Parameters")
});


task("Parameters:set", "Parameters set")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        let addr = await getDeployment(network.name, "Parameters");
        let p = await ethers.getContractAt("Parameters", addr, deployer);
        for(let index = 0; index < params.length; index++) {
            const element = params[index];
            await(await p.set(element.key, element.value)).wait();
            console.log(await p.get(element.key));
        }
});

let params = [
        {
            key: "OBSERVE_MAX_DELAY_BLOCK",
            value: 100
        },
        {
            key: "KEY_GEN_FAIL_JAIL_BLOCK",
            value: 50000
        },
        {
            key: "JAIL_BLOCK",
            value: 50000
        },
        {
            key: "OBSERVE_SLASH_POINT",
            value: 100
        },
        {
            key: "OBSERVE_DELAY_SLASH_POINT",
            value: 100
        },
        {
            key: "KEY_GEN_FAIL_SLASH_POINT",
            value: 1500
        },
        {
            key: "KEY_GEN_DELAY_SLASH_POINT",
            value: 1500
        },
        {
            key: "MIGRATION_DELAY_SLASH_POINT",
            value: 300
        },
        {
            key: "MIN_BLOCKS_PER_EPOCH",
            value: 5000
        },
        {
            key: "MAX_BLOCKS_FOR_UPDATE_TSS",
            value: 5000
        },
        {
            key: "REWARD_PER_BLOCK",
            value: 1
        },
        {
            key: "BLOCKS_PER_EPOCH",
            value: 10000
        },
        {
            key: "MAX_SLASH_POINT_FOR_ELECT",
            value: 1500
        },
        {
            key: "ADDITIONAL_REWARD_MAX_SLASH_POINT",
            value: 1500
        },
]



