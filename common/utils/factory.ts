/**
 * CREATE2 factory deployment — deterministic contract addresses across chains.
 * Used internally by evmHelper and tronHelper when salt is provided.
 * EVM factory: 0x6258e4d2950757A749a4d4683A7342261ce12471
 * Tron factory: TYWN3vHHuPxYfDDnshtuJTYxKMxhMkDm9P
 */
import { tronFromHex } from "./tronHelper";

// Factory contract addresses
const EVM_FACTORY = "0x6258e4d2950757A749a4d4683A7342261ce12471";
const TRON_FACTORY = "TYWN3vHHuPxYfDDnshtuJTYxKMxhMkDm9P";

// Factory ABI — works with both ethers.js and tronweb
// function deploy(bytes32 salt, bytes creationCode, uint256 value)
// function getAddress(bytes32 salt) view returns (address)
const FACTORY_ABI = [
    {
        "inputs": [{"name": "salt", "type": "bytes32"}, {"name": "creationCode", "type": "bytes"}, {"name": "value", "type": "uint256"}],
        "name": "deploy",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{"name": "salt", "type": "bytes32"}],
        "name": "getAddress",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function"
    }
];

// ============================================================
// EVM Factory (ethers.js)
// ============================================================

/**
 * Deploy contract via CREATE2 factory on EVM chains
 * @param ethers - ethers from hardhat runtime (hre.ethers)
 * @param salt - human-readable salt string
 * @param bytecode - contract bytecode (artifact.bytecode)
 * @param constructorArgs - ABI-encoded constructor arguments
 * @returns deployed contract address
 */
export async function evmDeployByFactory(
    ethers: any,
    salt: string,
    bytecode: string,
    constructorArgs: string = "0x"
): Promise<string> {
    const [signer] = await ethers.getSigners();
    const factory = new ethers.Contract(EVM_FACTORY, FACTORY_ABI, signer);

    const code = await ethers.provider.getCode(EVM_FACTORY);
    if (code === "0x") throw new Error("factory not deployed on this chain");

    const saltHash = ethers.keccak256(ethers.toUtf8Bytes(salt));
    const predicted = await factory.getAddress(saltHash);

    const existingCode = await ethers.provider.getCode(predicted);
    if (existingCode !== "0x") {
        console.log(`already deployed at ${predicted}`);
        return predicted;
    }

    const fullBytecode = constructorArgs === "0x"
        ? bytecode
        : ethers.concat([bytecode, constructorArgs]);

    const tx = await factory.deploy(saltHash, fullBytecode, 0);
    await tx.wait();

    console.log(`deployed via factory at ${predicted}`);
    return predicted;
}

/**
 * Get predicted factory address for a salt on EVM
 */
export async function evmGetFactoryAddress(ethers: any, salt: string): Promise<string> {
    const factory = new ethers.Contract(EVM_FACTORY, FACTORY_ABI, await ethers.provider);
    const saltHash = ethers.keccak256(ethers.toUtf8Bytes(salt));
    return factory.getAddress(saltHash);
}

// ============================================================
// Tron Factory (tronweb)
// ============================================================

/**
 * Deploy contract via CREATE2 factory on Tron
 * @param tronWeb - initialized tronweb instance
 * @param artifacts - hardhat artifacts
 * @param contractName - contract name to deploy
 * @param salt - human-readable salt string
 * @param args - constructor arguments array
 * @param feeLimit - tron fee limit
 * @returns deployed contract address (0x-prefixed hex)
 */
export async function tronDeployByFactory(
    tronWeb: any,
    artifacts: any,
    contractName: string,
    salt: string,
    args: any[] = [],
    feeLimit: number = 15_000_000_000
): Promise<string> {
    const factory = await tronWeb.contract(FACTORY_ABI, TRON_FACTORY);
    const saltHash = tronWeb.sha3(salt);

    // Check if already deployed
    const predicted = await factory.getAddress(saltHash).call();
    const predictedHex = predicted.replace(/^41/, "0x");
    const code = await tronWeb.trx.getContract(tronWeb.address.fromHex(predicted));
    if (code && code.bytecode) {
        console.log(`already deployed at ${tronFromHex(predicted)}`);
        return predictedHex;
    }

    // Build creation code with constructor args
    const artifact = await artifacts.readArtifact(contractName);
    let creationCode = artifact.bytecode;
    if (args.length > 0) {
        const iface = new (require("ethers").Interface)(artifact.abi);
        const encoded = iface.encodeDeploy(args);
        creationCode = creationCode + encoded.slice(2); // remove 0x prefix
    }

    console.log(`deploying ${contractName} via factory with salt "${salt}"...`);
    await factory.deploy(saltHash, creationCode, 0).send({ feeLimit });

    const addr = await factory.getAddress(saltHash).call();
    const addrHex = addr.replace(/^41/, "0x");
    console.log(`${contractName} deployed: ${tronFromHex(addr)} (${addrHex})`);
    return addrHex;
}

/**
 * Get predicted factory address for a salt on Tron
 * @returns address in base58 format
 */
export async function tronGetFactoryAddress(tronWeb: any, salt: string): Promise<string> {
    const factory = await tronWeb.contract(FACTORY_ABI, TRON_FACTORY);
    const saltHash = tronWeb.sha3(salt);
    const addr = await factory.getAddress(saltHash).call();
    return tronFromHex(addr);
}
