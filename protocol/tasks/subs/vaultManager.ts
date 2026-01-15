import { task } from "hardhat/config";
import { VaultManager } from "../../typechain-types/contracts"
import { getDeploymentByKey, getVaultFeeRate, getTokenRegsterByTokenName, getAllTokenRegster, getBalanceFeeRate } from "../utils/utils"

task("vaultManager:updateVaultFeeRate", "update Vault Fee Rate")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let vaultFeeRate = await getVaultFeeRate(network.name);
        let currentVaultFeeRate = await vaultManager.vaultFeeRate();
        if (currentVaultFeeRate === BigInt(vaultFeeRate)) {
            console.log(`vaultFeeRate already set to ${currentVaultFeeRate}, skipping`);
            return;
        }
        console.log(`on-chain vaultFeeRate: ${currentVaultFeeRate}, config vaultFeeRate: ${vaultFeeRate}, updating...`);
        await(await vaultManager.updateVaultFeeRate(vaultFeeRate)).wait()
        console.log(`after vaultFeeRate === `, await vaultManager.vaultFeeRate())
});

task("vaultManager:updateBalanceFeeRate", "update Balance Fee Rate")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let balanceFeeRate = await getBalanceFeeRate(network.name);
        let currentBalanceFeeRate = await vaultManager.balanceFeeRate();
        if (currentBalanceFeeRate === BigInt(balanceFeeRate)) {
            console.log(`balanceFeeRate already set to ${currentBalanceFeeRate}, skipping`);
            return;
        }
        console.log(`on-chain balanceFeeRate: ${currentBalanceFeeRate}, config balanceFeeRate: ${balanceFeeRate}, updating...`);
        await(await vaultManager.updateBalanceFeeRate(balanceFeeRate)).wait()
        console.log(`after balanceFeeRate === `, await vaultManager.balanceFeeRate())
});

task("vaultManager:setRelay", "set Relay address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let relay = await getDeploymentByKey(network.name, "Relay");
        let currentRelay = await vaultManager.relay();
        if (currentRelay.toLowerCase() === relay.toLowerCase()) {
            console.log(`relay already set to ${currentRelay}, skipping`);
            return;
        }
        console.log(`on-chain relay: ${currentRelay}, config relay: ${relay}, updating...`);
        await(await vaultManager.setRelay(relay)).wait()
        console.log(`after relay === `, await vaultManager.relay())
});

task("vaultManager:setRegistry", "set registry address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let registry = await getDeploymentByKey(network.name, "Registry");
        let currentRegistry = await vaultManager.registry();
        if (currentRegistry.toLowerCase() === registry.toLowerCase()) {
            console.log(`registry already set to ${currentRegistry}, skipping`);
            return;
        }
        console.log(`on-chain registry: ${currentRegistry}, config registry: ${registry}, updating...`);
        await(await vaultManager.setRegistry(registry)).wait()
        console.log(`after registry === `, await vaultManager.registry())
});

task("vaultManager:updateTokenWeights", "update Token Weights by token name")
    .addParam("token", "token name")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegister = await getTokenRegsterByTokenName(network.name, taskArgs.token);
        if(!tokenRegister) throw("token not exsit");
        if(!tokenRegister.chainWeights || tokenRegister.chainWeights.length === 0) throw("not chainWeights");

        let chains = tokenRegister.chainWeights.map(item => item.chainId);
        let weights = tokenRegister.chainWeights.map(item => item.weight);
        console.log(`token ${taskArgs.token} updateTokenWeights chains(${chains}), weights(${weights})`);
        await(await vaultManager.updateTokenWeights(tokenRegister.addr, chains, weights)).wait()
});

task("vaultManager:updateAllTokenWeights", "update Token Weights")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegisters = await getAllTokenRegster(network.name);
        if(!tokenRegisters || tokenRegisters.length === 0 ) throw("no token to register");
        for (let index = 0; index < tokenRegisters.length; index++) {
            const element = tokenRegisters[index];
            let chains = element.chainWeights.map(item => item.chainId);
            let weights = element.chainWeights.map(item => item.weight);
            console.log(`token ${element.name} updateTokenWeights chains(${chains}), weights(${weights})`);
            await(await vaultManager.updateTokenWeights(element.addr, chains, weights)).wait()
        }
});

task("vaultManager:setMinAmount", "update Token Weights by token name")
    .addParam("token", "token name")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegister = await getTokenRegsterByTokenName(network.name, taskArgs.token);
        if(!tokenRegister) throw("token not exsit");
        if(!tokenRegister.relayOutMinAmounts || tokenRegister.relayOutMinAmounts.length === 0) throw("not relayOutMinAmounts");

        for (let index = 0; index < tokenRegister.relayOutMinAmounts.length; index++) {
            const element = tokenRegister.relayOutMinAmounts[index];
            let currentMinAmount = await vaultManager.getRelayOutMinAmount(tokenRegister.addr, element.chainId);
            if (currentMinAmount === BigInt(element.minAmount)) {
                console.log(`setMinAmount token(${taskArgs.token}), chain(${element.chainId}) already set to ${element.minAmount}, skipping`);
                continue;
            }
            console.log(`setMinAmount token(${taskArgs.token}), chain(${element.chainId}), on-chain: ${currentMinAmount}, config: ${element.minAmount}, updating...`)
            await(await vaultManager.setMinAmount(tokenRegister.addr, element.chainId, element.minAmount)).wait()

        }

});

task("vaultManager:setAllMinAmount", "update Token Weights")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegisters = await getAllTokenRegster(network.name);
        if(!tokenRegisters || tokenRegisters.length === 0 ) throw("no token to register");
        for (let index = 0; index < tokenRegisters.length; index++) {
            const element = tokenRegisters[index];
            if(!element.relayOutMinAmounts || element.relayOutMinAmounts.length === 0) continue;
            for (let j = 0; j < element.relayOutMinAmounts.length; j++) {
                const r = element.relayOutMinAmounts[j];
                let currentMinAmount = await vaultManager.getRelayOutMinAmount(element.addr, r.chainId);
                if (currentMinAmount === BigInt(r.minAmount)) {
                    console.log(`setMinAmount token(${element.name}), chain(${r.chainId}) already set to ${r.minAmount}, skipping`);
                    continue;
                }
                console.log(`setMinAmount token(${element.name}), chain(${r.chainId}), on-chain: ${currentMinAmount}, config: ${r.minAmount}, updating...`)
                await(await vaultManager.setMinAmount(element.addr, r.chainId, r.minAmount)).wait()
            }
        }
});

task("vaultManager:registerToken", "register Token")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const VaultManagerFactory = await ethers.getContractFactory("VaultManager");
        let addr = await getDeploymentByKey(network.name, "VaultManager");
        const vaultManager = VaultManagerFactory.attach(addr) as VaultManager;
        let tokenRegisters = await getAllTokenRegster(network.name);
        if(!tokenRegisters || tokenRegisters.length === 0 ) throw("no token to register");

        for (let index = 0; index < tokenRegisters.length; index++) {
            const element = tokenRegisters[index];
            if(element.vaultToken.length > 0) {
               try {
                   let currentVaultToken = await vaultManager.getVaultToken(element.addr);
                   if (currentVaultToken.toLowerCase() === element.vaultToken.toLowerCase()) {
                       console.log(`registerToken ${element.name} already registered with vault(${currentVaultToken}), skipping`);
                       continue;
                   }
                   if (currentVaultToken !== "0x0000000000000000000000000000000000000000") {
                       console.log(`registerToken ${element.name} on-chain vault: ${currentVaultToken}, config vault: ${element.vaultToken}, updating...`);
                   }
               } catch (e) {
                   // Token not registered yet, proceed to register
               }
               console.log(`registerToken ${element.name} token(${element.addr}), vault(${element.vaultToken})`);
               await(await vaultManager.registerToken(element.addr, element.vaultToken)).wait();
            }
        }

});



