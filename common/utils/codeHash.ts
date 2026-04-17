/**
 * Calculate creationCode hash for CREATE2 address prediction.
 */
const { keccak256, Interface } = require("ethers");

/**
 * Get codeHash for a contract deployment.
 * @param artifacts - hardhat artifacts (hre.artifacts)
 * @param contractName - contract name (e.g. "Gateway", "AuthorityManager")
 * @param args - constructor arguments array
 */
export async function getCodeHash(artifacts: any, contractName: string, args: any[] = []): Promise<string> {
    const artifact = await artifacts.readArtifact(contractName);
    let bytecode = artifact.bytecode;
    if (!bytecode.startsWith("0x")) bytecode = "0x" + bytecode;

    if (args.length > 0) {
        const iface = new Interface(artifact.abi);
        const encoded = iface.encodeDeploy(args);
        return keccak256(bytecode + encoded.slice(2));
    }

    return keccak256(bytecode);
}

/**
 * Get codeHash for an ERC1967Proxy deployment.
 * @param artifacts - hardhat artifacts (hre.artifacts)
 * @param implAddress - implementation address
 * @param implName - implementation contract name (for encoding initData)
 * @param initArgs - arguments for initialize() function
 */
export async function getProxyCodeHash(
    artifacts: any,
    implAddress: string,
    implName: string,
    initArgs: any[] = []
): Promise<string> {
    return getCustomProxyCodeHash(artifacts, "ERC1967Proxy", implAddress, implName, initArgs);
}

/**
 * Get codeHash for a custom proxy deployment.
 * @param artifacts - hardhat artifacts (hre.artifacts)
 * @param proxyName - proxy contract name (e.g. "MyCustomProxy")
 * @param implAddress - implementation address
 * @param implName - implementation contract name (for encoding initData)
 * @param initArgs - arguments for initialize() function
 */
export async function getCustomProxyCodeHash(
    artifacts: any,
    proxyName: string,
    implAddress: string,
    implName: string,
    initArgs: any[] = []
): Promise<string> {
    const proxyArtifact = await artifacts.readArtifact(proxyName);
    let bytecode = proxyArtifact.bytecode;
    if (!bytecode.startsWith("0x")) bytecode = "0x" + bytecode;

    let initData = "0x";
    if (initArgs.length > 0) {
        const implArtifact = await artifacts.readArtifact(implName);
        const iface = new Interface(implArtifact.abi);
        initData = iface.encodeFunctionData("initialize", initArgs);
    }

    const { AbiCoder } = require("ethers");
    const constructorArgs = AbiCoder.defaultAbiCoder().encode(
        ["address", "bytes"],
        [implAddress, initData]
    );

    return keccak256(bytecode + constructorArgs.slice(2));
}
