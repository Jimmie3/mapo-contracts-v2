// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScript as CommonBaseScript, console} from "@mapprotocol/common-contracts/script/base/Base.s.sol";

/**
 * @title BaseScript
 * @notice Protocol-specific base, extends common BaseScript with verification helpers
 */
abstract contract BaseScript is CommonBaseScript {

    // Struct to store deployment info for verification
    struct DeploymentInfo {
        address proxy;
        address implementation;
        string contractName;
        bytes initData;
    }

    // Store deployments for batch verification
    DeploymentInfo[] internal deployments;

    // ==================== Verification Helpers ====================

    /**
     * @notice Store deployment info for later verification
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
}
