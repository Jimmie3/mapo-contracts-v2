import { task } from "hardhat/config";
import { getDeploymentByKey, saveDeployment } from "../utils/utils"
import { FusionReceiver } from "../../typechain-types/contracts/len/FusionReceiver.sol";


task("FusionReceiver:deploy", "deploy FusionReceiver")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const { createDeployer } = require("@mapprotocol/common-contracts/utils/deployer");

        let authority = await getDeploymentByKey(network.name, "Authority");
        if(!authority || authority.length == 0) throw("authority not deploy");
        let relay = await getDeploymentByKey(network.name, "Relay");
        if(!relay || relay.length == 0) throw("relay not deploy");

        const deployer = createDeployer(hre, { autoVerify: true });
        let result = await deployer.deployProxy("FusionReceiver", [authority]);
        console.log("FusionReceiver proxy:", result.proxy);
        console.log("FusionReceiver impl:", result.implementation);
        await saveDeployment(network.name, "FusionReceiver", result.proxy);

        const FusionReceiverFactory = await ethers.getContractFactory("FusionReceiver");
        let f = FusionReceiverFactory.attach(result.proxy) as FusionReceiver;
        let mos = "0x0000317Bec33Af037b5fAb2028f52d14658F6A56";
        await (await f.set(mos, relay)).wait();
});


task("FusionReceiver:emergencyWithdraw", "emergencyWithdraw")
    .addParam("token", "token address")
    .addParam("amount", "token amount")
    .addOptionalParam("receiver", "receiver address, default to deployer address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let addr = await getDeploymentByKey(network.name, "FusionReceiver");
        const FusionReceiverFactory = await ethers.getContractFactory("FusionReceiver");
        const r = FusionReceiverFactory.attach(addr) as FusionReceiver;
        // Set receiver address (default to sender)
        const receiver = taskArgs.receiver || await deployer.getAddress();
        let amount = ethers.parseUnits(taskArgs.amount, 18);
        await(await r.emergencyWithdraw(taskArgs.token, amount, receiver)).wait();
        console.log("...........done...........");
});

task("FusionReceiver:retry", "retry")
    .addParam("source", "from butter 0, from tss 1")
    .addParam("order", "orderId")
    .addParam("token", "token address")
    .addParam("amount", "token amount")
    .addParam("chain", "from chain id")
    .addParam("from", "from address")
    .addParam("payload", "payload")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let addr = await getDeploymentByKey(network.name, "FusionReceiver");
        const FusionReceiverFactory = await ethers.getContractFactory("FusionReceiver");
        const r = FusionReceiverFactory.attach(addr) as FusionReceiver;
        await(
            await r.retry(
                taskArgs.source, 
                taskArgs.order, 
                taskArgs.token, 
                taskArgs.amount, 
                taskArgs.chain, 
                taskArgs.from, 
                taskArgs.payload
            )
        ).wait();
        console.log("...........done...........");
});


task("FusionReceiver:retryWithHash", "retry a failed FusionReceiver store by tx hash")
    .addParam("hash", "failed transaction hash")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress());

        let addr = await getDeploymentByKey(network.name, "FusionReceiver");
        const FusionReceiverFactory = await ethers.getContractFactory("FusionReceiver");
        const r = FusionReceiverFactory.attach(addr) as FusionReceiver;

        let receipt = await deployer.provider.getTransactionReceipt(taskArgs.hash);
        if (!receipt) throw new Error("no receipt for tx: " + taskArgs.hash);

        const addrLower = addr.toLowerCase();
        let retried = false;
        for (const log of receipt.logs) {
            if (log.address.toLowerCase() !== addrLower) continue;
            let e;
            try {
                e = FusionReceiverFactory.interface.parseLog(log);
            } catch {
                continue;
            }
            if (!e || e.name !== "FailedStore") continue;

            // FailedStore(receiveType, orderId, token, amount, fromChain, from, payload)
            const [source, order, token, amount, chain, from, payload] = e.args;
            console.log("retrying FailedStore:", {
                source: source.toString(),
                order,
                token,
                amount: amount.toString(),
                chain: chain.toString(),
                from,
                payload,
            });
            await (await r.retry(source, order, token, amount, chain, from, payload)).wait();
            console.log("...........done...........");
            retried = true;
            break;
        }
        if (!retried) throw new Error("no FailedStore event found in tx logs");
});
