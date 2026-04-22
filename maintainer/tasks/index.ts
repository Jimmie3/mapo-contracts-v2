import "./subs/maintainers";
import "./subs/parameters";
import "./subs/tssManager";

import { task, types } from "hardhat/config";
import { getDeployment } from "./subs/utils";

task("upgrade", "upgrade contract")
    .addParam("contract", "contract name (Maintainers, Parameters, TSSManager)")
    .addParam("verify", "verify new impl after upgrade (true/false)", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        const { createDeployer } = require("@mapprotocol/common-contracts/utils/deployer");
        let addr = await getDeployment(network.name, taskArgs.contract);
        if (!addr || addr.length === 0) throw new Error("contract not deployed");
        const deployer = createDeployer(hre, { autoVerify: taskArgs.verify === "true" });
        let result = await deployer.upgrade(taskArgs.contract, addr);
        console.log(`${taskArgs.contract} upgraded, new impl:`, result.address);
    });