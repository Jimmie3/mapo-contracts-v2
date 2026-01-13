import { task } from "hardhat/config";
import { FlashSwapManager } from "../../typechain-types/contracts/len"
import { getDeploymentByKey, verify, saveDeployment } from "../utils/utils"

task("swapManager:deploy", "deploy vault token")
    .addParam("swap", "asset address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const FlashSwapManagerFactory = await ethers.getContractFactory("FlashSwapManager");
        let authority = await getDeploymentByKey(network.name, "Authority");
        if(!authority || authority.length == 0) throw("authority not deploy");

        let impl = await(await FlashSwapManagerFactory.deploy()).waitForDeployment();
        let init_data = FlashSwapManagerFactory.interface.encodeFunctionData("initialize", [authority]);
        let ContractProxy = await ethers.getContractFactory("ERC1967Proxy");
        let c = await (await ContractProxy.deploy(impl, init_data)).waitForDeployment();
        console.log("FlashSwapManager deploy to :", await c.getAddress());
        let v = FlashSwapManagerFactory.attach(await c.getAddress()) as FlashSwapManager;
        await saveDeployment(network.name, "SwapManager", await c.getAddress());
        console.log(`pre swap address is:`, await v.flashSwap());
        await (await v.setFlashSwap(taskArgs.swap)).wait();
        console.log(`after swap address is:`, await v.flashSwap());
      // await verify(hre, await c.getAddress(), [await impl.getAddress(), init_data], "contracts/ERC1967Proxy.sol:ERC1967Proxy");
       await verify(hre, await impl.getAddress(), [], "contracts/len/FlashSwapManager.sol:FlashSwapManager");
});



task("swapManager:upgradeTo", "upgrapde vault token contract")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const FlashSwapManagerFactory = await ethers.getContractFactory("FlashSwapManager");
        let addr = await getDeploymentByKey(network.name, "SwapManager");
        if(!addr || addr.length == 0) throw("vaultManager not deploy");
        let impl = await(await FlashSwapManagerFactory.deploy()).waitForDeployment();
        let v = FlashSwapManagerFactory.attach(addr) as FlashSwapManager;
        console.log("pre impl address is:", await v.getImplementation())
        await(await v.upgradeToAndCall(await impl.getAddress(), "0x")).wait()
        console.log("after impl address is:", await v.getImplementation())
        await verify(hre, await impl.getAddress(), [], "contracts/len/FlashSwapManager.sol:FlashSwapManager");
    })

task("swapManager:setFlashSwap", "upgrapde vault token contract")
    .addParam("swap", "flash swap address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const FlashSwapManagerFactory = await ethers.getContractFactory("FlashSwapManager");
        let addr = await getDeploymentByKey(network.name, "SwapManager");
        if(!addr || addr.length == 0) throw("vaultManager not deploy");
        let v = FlashSwapManagerFactory.attach(addr) as FlashSwapManager;
        console.log("pre flash swap address is:", await v.flashSwap())
        await(await v.setFlashSwap(taskArgs.swap)).wait()
        console.log("after flash swap address is:", await v.flashSwap())
    })