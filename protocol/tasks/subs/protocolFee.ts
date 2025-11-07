import { task } from "hardhat/config";
import { ProtocolFee } from "../../typechain-types/contracts"
import { getDeploymentByKey, getProtocolFeeConfig } from "./utils"

task("protocolFee:updateProtocolFee", "update Protocol Fee")
    .addOptionalParam("rate", "total fee rate")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const ProtocolFeeFactory = await ethers.getContractFactory("ProtocolFee");
        let addr = await getDeploymentByKey(network.name, "ProtocolFee");
        const protocolFee = ProtocolFeeFactory.attach(addr) as ProtocolFee;
        let totalRate;
        if(taskArgs.rate) {
            totalRate = taskArgs.rate;
        } else {
            totalRate = (await getProtocolFeeConfig(network.name)).totalRate
        }
        console.log("pre totalRate is", await protocolFee.totalRate());
        await(await protocolFee.updateProtocolFee(totalRate)).wait();
        console.log("after totalRate is", await protocolFee.totalRate());
});


task("protocolFee:updateTokens", "update Tokens")
    .addParam("token", "token address")
    .addParam("add", "true for add false for remove")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const ProtocolFeeFactory = await ethers.getContractFactory("ProtocolFee");
        let addr = await getDeploymentByKey(network.name, "ProtocolFee");
        const protocolFee = ProtocolFeeFactory.attach(addr) as ProtocolFee;
        await(await protocolFee.updateTokens([taskArgs.token], taskArgs.add)).wait()
});


task("protocolFee:updateShares", "update fee Shares")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const ProtocolFeeFactory = await ethers.getContractFactory("ProtocolFee");
        let addr = await getDeploymentByKey(network.name, "ProtocolFee");
        const protocolFee = ProtocolFeeFactory.attach(addr) as ProtocolFee;
        let configs = (await getProtocolFeeConfig(network.name)).feeShares;

        if(!configs || configs.length === 0) throw("fee config not set")

        let types = configs.map(item => item.feeType);
        let shares = configs.map(item => item.share);
        console.log(`updateShares types(${types}), shares(${shares})`);
        await(await protocolFee.updateShares(types, shares)).wait();
});

task("protocolFee:updateReceivers", "update fee Receivers")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const ProtocolFeeFactory = await ethers.getContractFactory("ProtocolFee");
        let addr = await getDeploymentByKey(network.name, "ProtocolFee");
        const protocolFee = ProtocolFeeFactory.attach(addr) as ProtocolFee;
        let configs = (await getProtocolFeeConfig(network.name)).feeShares;

        if(!configs || configs.length === 0) throw("fee config not set")

        let types = configs.map(item => item.feeType);
        let receivers = configs.map(item => item.receiver);
        console.log(`updateReceivers types(${types}), receivers(${receivers})`);
        await(await protocolFee.updateReceivers(types, receivers)).wait();
});




