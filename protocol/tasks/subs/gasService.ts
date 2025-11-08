import { task } from "hardhat/config";
import { GasService } from "../../typechain-types/contracts"
import { getDeploymentByKey } from "./utils"

task("gasService:setPeriphery", "set Periphery address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const GasServiceFactory = await ethers.getContractFactory("GasService");
        let addr = await getDeploymentByKey(network.name, "GasService");
        const gasSenvice = GasServiceFactory.attach(addr) as GasService;
        let periphery = await getDeploymentByKey(network.name, "Periphery");
        console.log("pre periphery is", await gasSenvice.periphery());
        await(await gasSenvice.setPeriphery(periphery)).wait();
        console.log("after periphery is", await gasSenvice.periphery());
});









