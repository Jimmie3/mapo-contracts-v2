import { task } from "hardhat/config";
import { Gateway } from "../../typechain-types/contracts"
import { getDeploymentByKey, getChainTokenByNetwork } from "./utils"

task("gateway:setWtoken", "set wtoken address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const GatewayFactory = await ethers.getContractFactory("Gateway");
        let addr;
        if(network.name === "Mapo" || network.name === "Makalu") {
            addr = await getDeploymentByKey(network.name, "Relay");
        } else {
            addr = await getDeploymentByKey(network.name, "Gateway");
        }
        const gateway = GatewayFactory.attach(addr) as Gateway;
        let wtoken = await getDeploymentByKey(network.name, "wToken");
        console.log(`pre wtoken address is: `, await gateway.wToken())
        await(await gateway.setWtoken(wtoken)).wait();
        console.log(`after wtoken address is: `, await gateway.wToken())
});

task("gateway:setTssAddress", "set tss pubkey")
    .addParam("pubkey", "tss pubkey")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const GatewayFactory = await ethers.getContractFactory("Gateway");
        let addr = await getDeploymentByKey(network.name, "Gateway");
        const gateway = GatewayFactory.attach(addr) as Gateway;
        console.log(`pre pubkey is: `, await gateway.activeTss())
        await(await gateway.setTssAddress(taskArgs.pubkey)).wait();
        console.log(`after pubkey is: `, await gateway.activeTss())
});


task("gateway:updateTokens", "update Tokens")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const GatewayFactory = await ethers.getContractFactory("Gateway");
        let addr;
        if(network.name === "Mapo" || network.name === "Makalu") {
            addr = await getDeploymentByKey(network.name, "Relay");
        } else {
            addr = await getDeploymentByKey(network.name, "Gateway");
        }
        
        const gateway = GatewayFactory.attach(addr) as Gateway;
        
        let tokens = (await getChainTokenByNetwork(network.name)).tokens
        if(!tokens || tokens.length == 0) return;
        for (let index = 0; index < tokens.length; index++) {
            const element = tokens[index];
            let feature = 0;
            if(element.bridgeAble) feature = feature | 1;
            if(element.mintAble) feature = feature | 2
            let pre = await gateway.tokenFeatureList(element.addr);
            console.log(`${element.name} pre tokenFeature`, pre);
            if(pre !==  BigInt(feature)) {
                console.log(`${element.name} after tokenFeature`, await gateway.tokenFeatureList(element.addr));
                await(await gateway.updateTokens([element.addr], feature)).wait();
            }
        } 
});


