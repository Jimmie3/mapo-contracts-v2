// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScript, console} from "./Base.s.sol";
import {Relay} from "../../contracts/Relay.sol";
import {VaultManager} from "../../contracts/VaultManager.sol";
import {ProtocolFee} from "../../contracts/ProtocolFee.sol";
import {Gateway} from "../../contracts/Gateway.sol";
import {GasService} from "../../contracts/GasService.sol";
import {Registry} from "../../contracts/Registry.sol";
import {ViewController} from "../../contracts/len/ViewController.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title VerifyContracts
 * @notice Script to generate verification commands for deployed contracts
 * @dev Uses foundry.toml [etherscan] config for API URLs
 *
 * Usage:
 *   forge script scripts/foundry/Verify.s.sol:VerifyContracts --rpc-url $RPC_URL -vvvv
 */
contract VerifyContracts is BaseScript {

    function run() public view {
        printVerifyCommands();
    }

    function printVerifyCommands() public view {
        uint256 chainId = block.chainid;
        (string memory env, string memory chain) = _resolveDeploymentPath();

        console.log("==============================================");
        console.log("Contract Verification Commands for:", string.concat(env, ".", chain));
        console.log("Chain ID:", chainId);
        console.log("==============================================\n");

        bool isBlockscout = (chainId == 212 || chainId == 22776);
        string memory verifierFlag = isBlockscout ? "--verifier blockscout " : "";

        if (chainId == 212 || chainId == 22776) {
            _printRelayChainCommands(chainId, verifierFlag);
        } else {
            _printGatewayCommands(chainId, verifierFlag);
        }

        console.log("\n# Note: Constructor args for proxy contracts need implementation address");
        console.log("# Use: cast abi-encode \"constructor(address,bytes)\" <IMPL> <INIT_DATA>");
    }

    function _printRelayChainCommands(
        uint256 chainId,
        string memory verifierFlag
    ) internal view {
        address authority = readDeployment("Authority");

        console.log("# --- Relay ---");
        address relay = readDeployment("Relay");
        _printCommand("Relay", "contracts/Relay.sol:Relay", relay, chainId, verifierFlag, authority);

        console.log("# --- VaultManager ---");
        address vaultManager = readDeployment("VaultManager");
        _printCommand("VaultManager", "contracts/VaultManager.sol:VaultManager", vaultManager, chainId, verifierFlag, authority);

        console.log("# --- ProtocolFee ---");
        address protocolFee = readDeployment("ProtocolFee");
        _printCommand("ProtocolFee", "contracts/ProtocolFee.sol:ProtocolFee", protocolFee, chainId, verifierFlag, authority);

        console.log("# --- GasService ---");
        address gasService = readDeployment("GasService");
        _printCommand("GasService", "contracts/GasService.sol:GasService", gasService, chainId, verifierFlag, authority);

        console.log("# --- Registry ---");
        address registry = readDeployment("Registry");
        _printCommand("Registry", "contracts/Registry.sol:Registry", registry, chainId, verifierFlag, authority);

        console.log("# --- ViewController ---");
        address viewController = readDeployment("ViewController");
        _printCommand("ViewController", "contracts/len/ViewController.sol:ViewController", viewController, chainId, verifierFlag, authority);
    }

    function _printGatewayCommands(
        uint256 chainId,
        string memory verifierFlag
    ) internal view {
        address authority = readDeployment("Authority");

        console.log("# --- Gateway ---");
        address gateway = readDeployment("Gateway");
        _printCommand("Gateway", "contracts/Gateway.sol:Gateway", gateway, chainId, verifierFlag, authority);
    }

    function _printCommand(
        string memory name,
        string memory contractPath,
        address proxyAddr,
        uint256 chainId,
        string memory verifierFlag,
        address authority
    ) internal pure {
        // Implementation verification
        console.log(string.concat("# Verify ", name, " implementation:"));
        console.log(string.concat(
            "forge verify-contract <IMPL_ADDRESS> ", contractPath,
            " ", verifierFlag, "--chain ", vm.toString(chainId)
        ));
        console.log("");

        // Proxy verification
        bytes memory initData = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), authority);
        console.log(string.concat("# Verify ", name, " proxy (", vm.toString(proxyAddr), "):"));
        console.log(string.concat(
            "forge verify-contract ", vm.toString(proxyAddr),
            " contracts/ERC1967Proxy.sol:ERC1967Proxy ",
            verifierFlag, "--chain ", vm.toString(chainId),
            " \\"
        ));
        console.log(string.concat(
            "  --constructor-args $(cast abi-encode \"constructor(address,bytes)\" <IMPL_ADDRESS> ",
            vm.toString(initData), ")"
        ));
        console.log("");
    }
}
