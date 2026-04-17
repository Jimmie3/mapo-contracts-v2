import "./subs/authority";

import { task, types } from "hardhat/config";
import { createDeployer } from "../utils/deployer";

task("contract:deploy", "deploy a contract")
    .addParam("contract", "contract name")
    .addOptionalParam("args", "constructor args as JSON array", "[]", types.string)
    .addOptionalParam("salt", "salt for factory deployment", "", types.string)
    .addOptionalParam("verify", "verify after deploy", "false", types.string)
    .setAction(async (taskArgs, hre) => {
        const deployer = createDeployer(hre, { autoVerify: taskArgs.verify === "true" });
        const args = JSON.parse(taskArgs.args);
        const result = await deployer.deploy(taskArgs.contract, args, taskArgs.salt);
        console.log(`${taskArgs.contract}: ${result.address}${result.hex ? ` (${result.hex})` : ""}`);
    });
