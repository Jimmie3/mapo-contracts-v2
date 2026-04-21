import { task } from "hardhat/config";
import { getDeploymentByKey, verify, saveDeployment } from "../utils/utils"
import { FusionReceiver } from "../../typechain-types/contracts/len/FusionReceiver.sol";


task("FusionReceiver:deploy", "deploy FusionReceiver")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        const FusionReceiverFactory = await ethers.getContractFactory("FusionReceiver");
        let authority = await getDeploymentByKey(network.name, "Authority");
        if(!authority || authority.length == 0) throw("authority not deploy");
        let relay = await getDeploymentByKey(network.name, "Relay");
        if(!relay || relay.length == 0) throw("relay not deploy");
        let impl = await(await FusionReceiverFactory.deploy()).waitForDeployment();
        let init_data = FusionReceiverFactory.interface.encodeFunctionData("initialize", [authority]);
        let ContractProxy = await ethers.getContractFactory("ERC1967Proxy");
        let c = await (await ContractProxy.deploy(impl, init_data)).waitForDeployment();
        console.log("FusionReceiver deploy to :", await c.getAddress());
        let f = FusionReceiverFactory.attach(await c.getAddress()) as FusionReceiver;
        await saveDeployment(network.name, "FusionReceiver", await c.getAddress());
        let mos = "0x0000317Bec33Af037b5fAb2028f52d14658F6A56";
        await (await f.set(mos, relay)).wait();
      // await verify(hre, await c.getAddress(), [await impl.getAddress(), init_data], "contracts/ERC1967Proxy.sol:ERC1967Proxy");
       await verify(hre, await impl.getAddress(), [], "contracts/len/FusionReceiver.sol:FusionReceiver");
});


task("FusionReceiver:emergencyWithdraw", "emergencyWithdraw")
    .addParam("token", "token address")
    .addParam("amount", "token amount")
    .addOptionalParam("receiver", "receiver address, default to deployer address")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let addr = "0xFe6Fc65c1B47be20bD776db55a412dF7520438F3"
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
        let addr = "0xFe6Fc65c1B47be20bD776db55a412dF7520438F3"
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


task("FusionReceiver:retryWithHash", "retry")
    .addParam("hash", "failed transaction hash")
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", await deployer.getAddress())
        let addr = "0xFe6Fc65c1B47be20bD776db55a412dF7520438F3"
        const FusionReceiverFactory = await ethers.getContractFactory("FusionReceiver");
        const r = FusionReceiverFactory.attach(addr) as FusionReceiver;
        let provide = deployer.provider;
        let receipt = await provide.getTransactionReceipt(taskArgs.hash);
        if(!receipt) throw("no receipts")
        let logs = receipt.logs;
        for (let index = 0; index < logs.length; index++) {
        const log = logs[index];
        if(log.address === addr) {
            let e = FusionReceiverFactory.interface.parseLog(log);
            if(!e) continue;
            if(e.name === "FailedStore") {
                let source = e.args[0].toString();
                let order = e.args[1];
                let token = e.args[2];
                let amount = e.args[3].toString();
                let chain = e.args[4].toString();
                let from = e.args[5];
                let payload = e.args[7];
                await(
                        await r.retry(
                            source, 
                            order, 
                            token, 
                            amount, 
                            chain, 
                            from, 
                            payload
                        )
                ).wait();
                console.log("...........done...........");
                break;
            } else {
                console.log("no FailedStore event found in transaction logs");
            }
        }

    }
    
});
