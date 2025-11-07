import { task } from "hardhat/config";
import { Periphery } from "../../typechain-types/contracts"
import { getDeploymentByKey } from "./utils"

task("periphery:set", "periphery set")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const PeripheryFactory = await ethers.getContractFactory("Periphery");
        let addr = await getDeploymentByKey(network.name, "Periphery");
        const periphery = PeripheryFactory.attach(addr) as Periphery;
        
        let tss = await getDeploymentByKey(network.name, "TSSManager");
        if(tss !== await periphery.tssManager()) {
            console.log(`update tss pre ${await periphery.tssManager()}, set to ${tss}`);
            await (await periphery.setTSSManager(tss)).wait();
        }
        let relay = await getDeploymentByKey(network.name, "Relay");
        if(relay !== await periphery.relay()) {
            console.log(`update relay pre ${await periphery.relay()}, set to ${relay}`);
            await (await periphery.setRelay(relay)).wait();
        }
        let vaultManager = await getDeploymentByKey(network.name, "VaultManager");
        if(vaultManager !== await periphery.vaultManager()) {
            console.log(`update vaultManager pre ${await periphery.vaultManager()}, set to ${vaultManager}`);
            await (await periphery.setVaultManager(vaultManager)).wait();
        }
        let gasService = await getDeploymentByKey(network.name, "GasService");
        if(gasService !== await periphery.gasService()) {
            console.log(`update gasService pre ${await periphery.gasService()}, set to ${gasService}`);
            await (await periphery.setGasService(gasService)).wait();
        }
        let registry = await getDeploymentByKey(network.name, "Registry");
        if(registry !== await periphery.tokenRegistry()) {
            console.log(`update registry pre ${await periphery.tokenRegistry()}, set to ${registry}`);
            await (await periphery.setTokenRegister(registry)).wait();
        }
        let affiliate = await getDeploymentByKey(network.name, "AffiliateManager");
        if(affiliate !== await periphery.affiliateManager()) {
            console.log(`update affiliate pre ${await periphery.affiliateManager()}, set to ${affiliate}`);
            await (await periphery.setAffiliateManager(affiliate)).wait();
        }
        let swap = await getDeploymentByKey(network.name, "SwapManager");
        if(swap !== await periphery.swapManager()) {
            console.log(`update swap pre ${await periphery.swapManager()}, set to ${swap}`);
            await (await periphery.setSwapManager(swap)).wait();
        }
        let protocolFee = await getDeploymentByKey(network.name, "ProtocolFee");
        if(protocolFee !== await periphery.protocolFeeManager()) {
            console.log(`update protocolFee pre ${await periphery.protocolFeeManager()}, set to ${protocolFee}`);
            await (await periphery.setProtocolFeeManager(protocolFee)).wait();
        }
});







