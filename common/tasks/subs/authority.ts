import { task, types } from "hardhat/config";
import { getDeploymentByKey, saveDeployment } from "../utils/utils";
import { tronDeploy, getTronContract, tronToHex, tronFromHex, isTronNetwork } from "../utils/tronUtil";

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

    let authority;
    if (isTronNetwork(hre.network.name)) {
        authority = await getTronContract("AuthorityManager", hre.artifacts, hre.network.name, addr);
    } else {
        const { ethers } = hre;
        authority = await ethers.getContractAt("AuthorityManager", addr);
    }
    return authority;
}

task("auth:deploy", "deploy AuthorityManager")
    .addOptionalParam("admin", "default admin address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        const { network, ethers } = hre;
        const [deployer] = await ethers.getSigners();
        console.log("deployer address:", deployer.address);

        let admin = taskArgs.admin;
        if (admin === "") {
            admin = deployer.address;
        }

        if (isTronNetwork(network.name)) {
            let adminHex = await tronToHex(admin, network.name);
            let addr = await tronDeploy("AuthorityManager", [adminHex], hre.artifacts, network.name);
            let tronAddr = await tronFromHex(addr, network.name);
            await saveDeployment(network.name, "Authority", tronAddr);
            console.log(`AuthorityManager deployed: ${tronAddr}`);
        } else {
            const AuthorityFactory = await ethers.getContractFactory("AuthorityManager");
            let authority = await (await AuthorityFactory.deploy(admin)).waitForDeployment();
            let addr = await authority.getAddress();
            await saveDeployment(network.name, "Authority", addr);
            console.log(`AuthorityManager deployed: ${addr}`);
        }
    });

task("auth:grant", "grant role to account")
    .addParam("account", "account to grant role")
    .addParam("role", "role name: admin/manager/minter")
    .addOptionalParam("delay", "execution delay", 0, types.int)
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        let authority = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);

        let account = taskArgs.account;
        if (isTronNetwork(network.name)) {
            account = await tronToHex(account, network.name);
            await authority.grantRole(role, account, taskArgs.delay).send();
        } else {
            await (await authority.grantRole(role, account, taskArgs.delay)).wait();
        }
        console.log(`granted role ${taskArgs.role}(${role}) to ${taskArgs.account}`);
    });

task("auth:revoke", "revoke role from account")
    .addParam("account", "account to revoke role")
    .addParam("role", "role name: admin/manager/minter")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        let authority = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);

        let account = taskArgs.account;
        if (isTronNetwork(network.name)) {
            account = await tronToHex(account, network.name);
            await authority.revokeRole(role, account).send();
        } else {
            await (await authority.revokeRole(role, account)).wait();
        }
        console.log(`revoked role ${taskArgs.role}(${role}) from ${taskArgs.account}`);
    });

task("auth:getMember", "get role members")
    .addOptionalParam("role", "role name", "admin", types.string)
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        let authority = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);

        if (isTronNetwork(hre.network.name)) {
            let count = await authority.getRoleMemberCount(role).call();
            console.log(`role ${taskArgs.role}(${role}) has ${count} member(s)`);
            for (let i = 0; i < count; i++) {
                let member = await authority.getRoleMember(role, i).call();
                console.log(`  ${i}: ${member}`);
            }
        } else {
            let count = await authority.getRoleMemberCount(role);
            console.log(`role ${taskArgs.role}(${role}) has ${count} member(s)`);
            for (let i = 0; i < count; i++) {
                let member = await authority.getRoleMember(role, i);
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
        const { network } = hre;
        let authority = await getAuth(hre, taskArgs.auth);
        let role = getRole(taskArgs.role);
        let funSigs = taskArgs.funcs.split(",");

        let target = taskArgs.target;
        if (isTronNetwork(network.name)) {
            target = await tronToHex(target, network.name);
            await authority.setTargetFunctionRole(target, funSigs, role).send();
        } else {
            await (await authority.setTargetFunctionRole(target, funSigs, role)).wait();
        }
        console.log(`set target ${taskArgs.target} functions [${funSigs}] to role ${taskArgs.role}(${role})`);
    });

task("auth:setAuth", "update target authority")
    .addParam("target", "target contract address")
    .addParam("addr", "new authority address")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        let authority = await getAuth(hre, taskArgs.auth);

        if (isTronNetwork(network.name)) {
            let target = await tronToHex(taskArgs.target, network.name);
            let newAuth = await tronToHex(taskArgs.addr, network.name);
            await authority.updateAuthority(target, newAuth).send();
        } else {
            await (await authority.updateAuthority(taskArgs.target, taskArgs.addr)).wait();
        }
        console.log(`set target ${taskArgs.target} authority to ${taskArgs.addr}`);
    });

task("auth:closeTarget", "close/open target")
    .addParam("target", "target contract address")
    .addParam("close", "true to close, false to open")
    .addOptionalParam("auth", "authority address", "", types.string)
    .setAction(async (taskArgs, hre) => {
        const { network } = hre;
        let authority = await getAuth(hre, taskArgs.auth);
        let close = taskArgs.close === "true";

        if (isTronNetwork(network.name)) {
            let target = await tronToHex(taskArgs.target, network.name);
            await authority.setTargetClosed(target, close).send();
        } else {
            await (await authority.setTargetClosed(taskArgs.target, close)).wait();
        }
        console.log(`set target ${taskArgs.target} closed: ${close}`);
    });
