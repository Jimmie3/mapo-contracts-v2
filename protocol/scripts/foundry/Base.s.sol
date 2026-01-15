// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { IFactory } from "./interfaces/IFactory.sol";
import { Script, stdJson, console } from "forge-std/Script.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC1967Proxy } from "../../contracts/ERC1967Proxy.sol";


/**
 * @title BaseScript
 * @notice Base contract for deployment scripts with verification support
 * @dev Supports both Blockscout (MAPO) and Etherscan-compatible explorers
 *
 * Verification Examples:
 *
 * 1. MAPO Mainnet (Blockscout):
 *    forge verify-contract <ADDRESS> <CONTRACT> \
 *      --verifier blockscout \
 *      --verifier-url https://explorer-api.chainservice.io/api
 *
 * 2. MAPO Testnet (Blockscout):
 *    forge verify-contract <ADDRESS> <CONTRACT> \
 *      --verifier blockscout \
 *      --verifier-url https://testnet-explorer-api.chainservice.io/api
 *
 * 3. Etherscan-compatible chains:
 *    forge verify-contract <ADDRESS> <CONTRACT> \
 *      --etherscan-api-key $API_KEY \
 *      --chain-id <CHAIN_ID>
 */
abstract contract BaseScript is Script {
    IFactory constant private factory = IFactory(0x6258e4d2950757A749a4d4683A7342261ce12471);
    using stdJson for string;
    address internal broadcaster;
    uint256 private broadcasterPK;

    // Struct to store deployment info for verification
    struct DeploymentInfo {
        address proxy;
        address implementation;
        string contractName;
        bytes initData;
    }

    // Store deployments for batch verification
    DeploymentInfo[] internal deployments;

    constructor() {
        uint256 privateKey;
        if (block.chainid == 212) {
            privateKey = vm.envUint("TESTNET_PRIVATE_KEY");
        } else {
            privateKey = vm.envUint("PRIVATE_KEY");
        }

        broadcaster = vm.addr(privateKey);
        broadcasterPK = privateKey;
    }

    modifier broadcast() {
        vm.startBroadcast(broadcasterPK);
        _;
        vm.stopBroadcast();
    }

    function deployProxyByFactory(string memory salt, address impl, bytes memory initData) internal returns(address addr) {
        addr = deployByFactory(salt, type(ERC1967Proxy).creationCode, abi.encode(impl, initData));
    }

    function deployByFactory(string memory salt, bytes memory creationCode, bytes memory param) internal returns(address addr) {
        addr = factory.getAddress(keccak256(bytes(salt)));
        if(addr.code.length > 0 ) revert ("addr already exist");
        bytes memory code = abi.encodePacked(creationCode, param);
        factory.deploy(keccak256(bytes(salt)), code, 0);
    }

    function deployProxy(address impl, bytes memory initData)  internal returns(address) {
        ERC1967Proxy p = new ERC1967Proxy(impl, initData);
        return address(p);
    }

    function readConfigAddr(string memory networkName, string memory key) internal view returns(address addr) {
        string memory configPath = "deployments/deploy.json";
        if (!vm.exists(configPath)) {
            revert(string(abi.encodePacked("Config file not found: ", configPath)));
        }
        string memory config = vm.readFile(configPath);
        string memory path = string(abi.encodePacked(".", networkName, ".", key));
        addr = config.readAddress(path);
    }

    function readConfigUint(string memory networkName, string memory key) internal view returns(uint256 v) {
        string memory configPath = "deployments/deploy.json";
        if (!vm.exists(configPath)) {
            revert(string(abi.encodePacked("Config file not found: ", configPath)));
        }
        string memory config = vm.readFile(configPath);
        string memory path = string(abi.encodePacked(".", networkName, ".", key));
        v = config.readUint(path);
    }

    function saveConfig(string memory networkName, string memory key, address addr) internal {
        string memory configPath = "deployments/deploy.json";
        string memory path = string(abi.encodePacked(".", networkName, ".", key));
        string memory json = vm.readFile(configPath);
        bool exists = vm.keyExistsJson(json, path);
        string memory addrStr = vm.toString(addr);
        if(exists) {
            vm.writeJson(addrStr, configPath, path);
        } else {
            revert(string(abi.encodePacked("key:", key, "not exists")));
        }
    }

    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        string memory suffix = vm.envOr("NETWORK_SUFFIX", string(""));
        bool isMain = keccak256(bytes(suffix)) == keccak256(bytes("main"));
        if(chainId == 212) return "Mapo_test";
        if(chainId == 11155111) return "Eth_test";
        if(chainId == 97) return "Bsc_test";

        
        if(chainId == 22776) {
            if(isMain) {
                return "Mapo_main";
            } else {
                return "Mapo_prod";
            }
        } 
        if(chainId == 1) {
            if(isMain) {
                return "Eth_main";
            } else {
                return "Eth_prod";
            }
        } 
        
        if(chainId == 56) {
            if(isMain) {
                return "Bsc_main";
            } else {
                return "Bsc_prod";
            }
        }
        
        if(chainId == 8453){
            if(isMain) {
                return "Base_main";
            } else {
                return "Base_prod";
            }
        }

        if(chainId == 42161){
            if(isMain) {
                return "Arb_main";
            } else {
                return "Arb_prod";
            }
        }
        revert("unknown");
    }

    // ==================== Verification Helpers ====================

    /**
     * @notice Store deployment info for later verification
     * @param proxy The proxy contract address
     * @param implementation The implementation contract address
     * @param contractName The contract name for verification
     * @param initData The initialization data used in proxy constructor
     */
    function _recordDeployment(
        address proxy,
        address implementation,
        string memory contractName,
        bytes memory initData
    ) internal {
        deployments.push(DeploymentInfo({
            proxy: proxy,
            implementation: implementation,
            contractName: contractName,
            initData: initData
        }));
    }

    /**
     * @notice Print verification commands for all recorded deployments
     * @dev Uses foundry.toml [etherscan] config for API URLs
     */
    function printVerificationCommands() internal view {
        uint256 chainId = block.chainid;
        bool isBlockscout = (chainId == 212 || chainId == 22776);
        string memory verifierFlag = isBlockscout ? "--verifier blockscout " : "";

        console.log("\n========== VERIFICATION COMMANDS ==========\n");

        for (uint256 i = 0; i < deployments.length; i++) {
            DeploymentInfo memory info = deployments[i];

            // Print implementation verification
            console.log(string.concat("# Verify ", info.contractName, " Implementation"));
            console.log(string.concat(
                "forge verify-contract ",
                vm.toString(info.implementation),
                " contracts/", info.contractName, ".sol:",
                _getContractNameFromPath(info.contractName),
                " ", verifierFlag, "--chain ", vm.toString(chainId)
            ));
            console.log("");

            // Print proxy verification
            if (info.proxy != address(0)) {
                bytes memory constructorArgs = abi.encode(info.implementation, info.initData);
                console.log(string.concat("# Verify ", info.contractName, " Proxy"));
                console.log(string.concat(
                    "forge verify-contract ",
                    vm.toString(info.proxy),
                    " contracts/ERC1967Proxy.sol:ERC1967Proxy ",
                    verifierFlag, "--chain ", vm.toString(chainId),
                    " --constructor-args ", vm.toString(constructorArgs)
                ));
                console.log("");
            }
        }

        console.log("============================================\n");
    }

    /**
     * @notice Extract contract name from path (e.g., "len/ViewController" -> "ViewController")
     */
    function _getContractNameFromPath(string memory path) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(path);
        uint256 lastSlash = 0;
        for (uint256 i = 0; i < pathBytes.length; i++) {
            if (pathBytes[i] == "/") {
                lastSlash = i + 1;
            }
        }
        if (lastSlash == 0) return path;

        bytes memory result = new bytes(pathBytes.length - lastSlash);
        for (uint256 i = lastSlash; i < pathBytes.length; i++) {
            result[i - lastSlash] = pathBytes[i];
        }
        return string(result);
    }

    /**
     * @notice Check if current chain uses Blockscout explorer
     * @return True if chain uses Blockscout
     */
    function _isBlockscoutChain() internal view returns (bool) {
        uint256 chainId = block.chainid;
        return (chainId == 212 || chainId == 22776);
    }
}
