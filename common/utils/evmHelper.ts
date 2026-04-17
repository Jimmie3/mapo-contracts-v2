/**
 * Deploy contract on EVM. If salt is provided, uses CREATE2 factory for deterministic address.
 * @param ethers - ethers from hardhat runtime (hre.ethers)
 * @param artifacts - hardhat artifacts (hre.artifacts)
 * @param contractName - contract name to deploy
 * @param args - constructor arguments array
 * @param salt - optional CREATE2 salt for deterministic address
 * @returns deployed contract address (0x hex)
 */
export async function evmDeploy(
    ethers: any,
    artifacts: any,
    contractName: string,
    args: any[] = [],
    salt: string = ""
): Promise<string> {
    if (salt) {
        const { evmDeployByFactory } = require("./factory");
        const artifact = await artifacts.readArtifact(contractName);
        const constructorArgs = args.length > 0
            ? ethers.AbiCoder.defaultAbiCoder().encode(
                artifact.abi
                    .find((x: any) => x.type === "constructor")
                    ?.inputs.map((i: any) => i.type) || [],
                args
            )
            : "0x";
        return evmDeployByFactory(ethers, salt, artifact.bytecode, constructorArgs);
    }

    const [deployer] = await ethers.getSigners();
    console.log("deploy address is:", deployer.address);

    const ContractFactory = await ethers.getContractFactory(contractName);
    const contract = await (await ContractFactory.deploy(...args)).waitForDeployment();
    const addr = await contract.getAddress();
    console.log(`${contractName} deployed: ${addr}`);
    return addr;
}

/**
 * Deploy implementation + ERC1967 proxy in one step.
 * If salt is provided, proxy is deployed via factory.
 * @param ethers - ethers from hardhat runtime (hre.ethers)
 * @param artifacts - hardhat artifacts (hre.artifacts)
 * @param contractName - implementation contract name
 * @param initArgs - initialize() function arguments
 * @param salt - optional CREATE2 salt for proxy
 * @returns { proxy, implementation } addresses
 */
export async function evmDeployProxy(
    ethers: any,
    artifacts: any,
    contractName: string,
    initArgs: any[] = [],
    salt: string = ""
): Promise<{ proxy: string; implementation: string }> {
    const ImplFactory = await ethers.getContractFactory(contractName);
    const impl = await (await ImplFactory.deploy()).waitForDeployment();
    const implAddr = await impl.getAddress();
    console.log(`${contractName} implementation: ${implAddr}`);

    const initData = ImplFactory.interface.encodeFunctionData("initialize", initArgs);

    let proxyAddr: string;
    if (salt) {
        const { evmDeployByFactory } = require("./factory");
        const proxyArtifact = await artifacts.readArtifact("ERC1967Proxy");
        const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "bytes"],
            [implAddr, initData]
        );
        proxyAddr = await evmDeployByFactory(ethers, salt, proxyArtifact.bytecode, constructorArgs);
    } else {
        const ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
        const proxy = await (await ProxyFactory.deploy(implAddr, initData)).waitForDeployment();
        proxyAddr = await proxy.getAddress();
    }

    console.log(`${contractName} proxy: ${proxyAddr}`);
    return { proxy: proxyAddr, implementation: implAddr };
}

/**
 * Upgrade a UUPS proxy to a new implementation.
 * Deploys new implementation, then calls upgradeToAndCall on the proxy.
 * @param ethers - ethers from hardhat runtime (hre.ethers)
 * @param contractName - new implementation contract name
 * @param proxyAddr - proxy address to upgrade
 * @returns new implementation address
 */
export async function evmUpgradeProxy(
    ethers: any,
    contractName: string,
    proxyAddr: string
): Promise<string> {
    const [deployer] = await ethers.getSigners();
    const ImplFactory = await ethers.getContractFactory(contractName);
    const impl = await (await ImplFactory.deploy()).waitForDeployment();
    const implAddr = await impl.getAddress();

    const proxy = await ethers.getContractAt("BaseImplementation", proxyAddr, deployer);
    const oldImpl = await proxy.getImplementation();
    await (await proxy.upgradeToAndCall(implAddr, "0x")).wait();

    console.log(`${contractName} upgraded: ${oldImpl} -> ${implAddr}`);
    return implAddr;
}
