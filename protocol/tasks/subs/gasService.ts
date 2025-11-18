import { task } from "hardhat/config";
import { GasService } from "../../typechain-types/contracts"
import { getDeploymentByKey } from "./utils"

task("gasService:setRegistry", "set registry address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const GasServiceFactory = await ethers.getContractFactory("GasService");
        let addr = await getDeploymentByKey(network.name, "GasService");
        const gasSenvice = GasServiceFactory.attach(addr) as GasService;
        let registry = await getDeploymentByKey(network.name, "Registry");
        console.log("pre registry is", await gasSenvice.registry());
        await(await gasSenvice.setRegistry(registry)).wait();
        console.log("after registry is", await gasSenvice.registry());
});









