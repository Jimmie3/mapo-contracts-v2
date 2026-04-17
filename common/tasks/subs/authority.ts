import { task, types } from "hardhat/config";
import { getDeploymentByKey as _getDeploymentByKey, saveDeployment as _saveDeployment } from "../../utils/deployRecord";

function getEnv() {
    const env = process.env.NETWORK_ENV;
    if (!env) throw new Error("NETWORK_ENV is required. Set to test/prod/main in .env");
    return env;
}
const getDeploymentByKey = (network: string, key: string) => _getDeploymentByKey(network, key, { env: getEnv() });
const saveDeployment = (network: string, key: string, addr: string) => _saveDeployment(network, key, addr, { env: getEnv() });
import { TronClient, tronToHex, isTronNetwork } from "../../utils/tronHelper";
import { createDeployer } from "../../utils/deployer";

function getRole(role: string): number {
    if (role === "root") return 0;
    if (role === "admin") return 1;
    if (role === "manager") return 2;
    if (role === "minter") return 10;
    throw "unknown role";
}

async function getAuth(hre: any, contractAddress: string) {
    let addr = contractAddress;
    if (addr === "" || addr === "latest") {
        addr = await getDeploymentByKey(hre.network.name, "Authority");
    }

    if (isTronNetwork(hre.network.name)) {
        let client = TronClient.fromHre(hre);
        let contract = await client.getContract(hre.artifacts, "AuthorityManager", addr);
        return { contract, isTron: true, client };
    } else {
        let contract = await hre.ethers.getContractAt("AuthorityManager", addr);
        return { contract, isTron: false, client: null as any };
    }
}

task("auth:deploy", "deploy AuthorityManager")
    .addOptionalParam("admin", "default admin address", "", types.string)
    .addOptionalParam("salt", "salt for factory deployment (enables CREATE2)", "", types.string)
    .addOptionalParam("verify", "verify contract after deploy", "false", types.string)
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", deployer.address);

        let admin = taskArgs.admin || deployer.address;
        const d = createDeployer(hre, { autoVerify: taskArgs.verify === "true" });

        // Tron needs hex address for constructor args
        let adminArg = d.isTron ? tronToHex(admin) : admin;
        let result = await d.deploy("AuthorityManager", [adminArg], taskArgs.salt);
        await saveDeployment(network.name, "Authority", result.address);
        console.log(`AuthorityManager deployed: ${result.address}${result.hex ? ` (${result.hex})` : ""}`);
    });

task("auth:grant", "grant role to account")
    .addParam("account", "account to grant role")
    .addParam("role", "role name: admin/manager/minter")
    .addOptionalParam("delay", "execution delay", 0, types.int)
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let { contract, isTron } = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);
        let account = isTron ? tronToHex(taskArgs.account) : taskArgs.account;

        if (isTron) {
            await contract.grantRole(role, account, taskArgs.delay).sendAndWait();
        } else {
            await (await contract.grantRole(role, account, taskArgs.delay)).wait();
        }
        console.log(`granted role ${taskArgs.role}(${role}) to ${taskArgs.account}`);
    });

task("auth:revoke", "revoke role from account")
    .addParam("account", "account to revoke role")
    .addParam("role", "role name: admin/manager/minter")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let { contract, isTron } = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);
        let account = isTron ? tronToHex(taskArgs.account) : taskArgs.account;

        if (isTron) {
            await contract.revokeRole(role, account).sendAndWait();
        } else {
            await (await contract.revokeRole(role, account)).wait();
        }
        console.log(`revoked role ${taskArgs.role}(${role}) from ${taskArgs.account}`);
    });

task("auth:getMember", "get role members")
    .addOptionalParam("role", "role name", "admin", types.string)
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let { contract, isTron } = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);

        if (isTron) {
            let count = await contract.getRoleMemberCount(role).call();
            console.log(`role ${taskArgs.role}(${role}) has ${count} member(s)`);
            for (let i = 0; i < count; i++) {
                let member = await contract.getRoleMember(role, i).call();
                console.log(`  ${i}: ${member}`);
            }
        } else {
            let count = await contract.getRoleMemberCount(role);
            console.log(`role ${taskArgs.role}(${role}) has ${count} member(s)`);
            for (let i = 0; i < count; i++) {
                let member = await contract.getRoleMember(role, i);
                console.log(`  ${i}: ${member}`);
            }
        }
    });

task("auth:setTarget", "set target function role")
    .addParam("target", "target contract address")
    .addParam("funcs", "function selectors (comma-separated)")
    .addParam("role", "role name")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let { contract, isTron } = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);
        let funSigs = taskArgs.funcs.split(",");
        let target = isTron ? tronToHex(taskArgs.target) : taskArgs.target;

        if (isTron) {
            await contract.setTargetFunctionRole(target, funSigs, role).sendAndWait();
        } else {
            await (await contract.setTargetFunctionRole(target, funSigs, role)).wait();
        }
        console.log(`set target ${taskArgs.target} functions [${funSigs}] to role ${taskArgs.role}(${role})`);
    });

task("auth:setAuth", "update target authority")
    .addParam("target", "target contract address")
    .addParam("addr", "new authority address")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let { contract, isTron } = await getAuth(hre, taskArgs.auth);
        let target = isTron ? tronToHex(taskArgs.target) : taskArgs.target;
        let newAuth = isTron ? tronToHex(taskArgs.addr) : taskArgs.addr;

        if (isTron) {
            await contract.updateAuthority(target, newAuth).sendAndWait();
        } else {
            await (await contract.updateAuthority(taskArgs.target, taskArgs.addr)).wait();
        }
        console.log(`set target ${taskArgs.target} authority to ${taskArgs.addr}`);
    });

task("auth:closeTarget", "close/open target")
    .addParam("target", "target contract address")
    .addParam("close", "true to close, false to open")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let { contract, isTron } = await getAuth(hre, taskArgs.auth);
        let close = taskArgs.close === "true";
        let target = isTron ? tronToHex(taskArgs.target) : taskArgs.target;

        if (isTron) {
            await contract.setTargetClosed(target, close).sendAndWait();
        } else {
            await (await contract.setTargetClosed(taskArgs.target, close)).wait();
        }
        console.log(`set target ${taskArgs.target} closed: ${close}`);
    });
