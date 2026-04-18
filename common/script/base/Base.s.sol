// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/**
 * @title BaseScript
 * @notice Base contract for deployment scripts with full lifecycle support
 * @dev Inherit this in your deployment scripts.
 *
 * Features:
 *   - Private key management (mainnet / testnet)
 *   - Direct deployment and CREATE2 factory deployment
 *   - Proxy deployment (implementation + ERC1967Proxy)
 *   - UUPS proxy upgrade
 *   - deploy.json record read/write
 *
 * Usage:
 *   contract MyDeploy is BaseScript {
 *       function run() public broadcast {
 *           // Direct deploy
 *           address impl = deployDirect(type(MyContract).creationCode, abi.encode(arg));
 *
 *           // Factory deploy (deterministic address)
 *           address addr = deployByFactory("my_salt", type(MyContract).creationCode, abi.encode(arg));
 *
 *           // Proxy deploy (impl + proxy)
 *           (address proxy, address impl) = deployProxy(type(MyContract).creationCode, initData);
 *           (address proxy, address impl) = deployProxyByFactory("my_salt", type(MyContract).creationCode, initData);
 *
 *           // Upgrade
 *           upgradeProxy(proxy, newImplAddr);
 *           address newImpl = deployAndUpgrade(proxy, type(MyContractV2).creationCode);
 *
 *           // Deploy record
 *           address relay = readDeployment("Relay");
 *           saveDeployment("Gateway", addr);
 *       }
 *   }
 */
abstract contract BaseScript is Script {
    IFactory constant private FACTORY = IFactory(0x6258e4d2950757A749a4d4683A7342261ce12471);
    using stdJson for string;

    address internal broadcaster;
    uint256 private broadcasterPK;

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

    // ============================================================
    // Factory (CREATE2) deployment
    // ============================================================

    /// @notice Deploy contract via CREATE2 factory with deterministic address
    function deployByFactory(
        string memory salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address addr) {
        require(address(FACTORY).code.length > 0, "factory not deployed on this chain");
        bytes32 saltHash = keccak256(bytes(salt));
        addr = FACTORY.getAddress(saltHash);
        if (addr.code.length > 0) revert("already deployed");
        bytes memory code = abi.encodePacked(creationCode, constructorArgs);
        FACTORY.deploy(saltHash, code, 0);
    }

    /// @notice Deploy implementation + proxy via CREATE2 factory
    function deployProxyByFactory(
        string memory salt,
        bytes memory implCreationCode,
        bytes memory initData
    ) internal returns (address proxy, address impl) {
        impl = deployDirect(implCreationCode, bytes(""));
        proxy = deployByFactory(salt, type(ERC1967Proxy).creationCode, abi.encode(impl, initData));
        console.log("Proxy:", proxy);
        console.log("Implementation:", impl);
    }

    /// @notice Check if the CREATE2 factory is available on this chain
    function isFactoryAvailable() internal view returns (bool) {
        return address(FACTORY).code.length > 0;
    }

    /// @notice Get the predicted address for a given salt
    function getFactoryAddress(string memory salt) internal view returns (address) {
        require(isFactoryAvailable(), "factory not deployed on this chain");
        return FACTORY.getAddress(keccak256(bytes(salt)));
    }

    /// @notice Check if a contract is already deployed at the factory address
    function isFactoryDeployed(string memory salt) internal view returns (bool) {
        if (!isFactoryAvailable()) return false;
        return FACTORY.getAddress(keccak256(bytes(salt))).code.length > 0;
    }

    // ============================================================
    // Direct deployment
    // ============================================================

    /// @notice Deploy a new contract directly (non-deterministic address)
    function deployDirect(
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address addr) {
        bytes memory code = abi.encodePacked(creationCode, constructorArgs);
        assembly {
            addr := create(0, add(code, 0x20), mload(code))
        }
        require(addr != address(0), "deploy failed");
    }

    /// @notice Deploy implementation + proxy directly
    function deployProxy(
        bytes memory implCreationCode,
        bytes memory initData
    ) internal returns (address proxy, address impl) {
        impl = deployDirect(implCreationCode, bytes(""));
        ERC1967Proxy p = new ERC1967Proxy(impl, initData);
        proxy = address(p);
        console.log("Proxy:", proxy);
        console.log("Implementation:", impl);
    }

    // ============================================================
    // Upgrade
    // ============================================================

    /// @notice Upgrade a UUPS proxy to a new implementation
    function upgradeProxy(address proxy, address newImpl) internal {
        address oldImpl = _getImplementation(proxy);
        (bool success,) = proxy.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, bytes(""))
        );
        require(success, "upgrade failed");
        console.log("Upgraded:", oldImpl, "->", newImpl);
    }

    /// @notice Deploy new implementation and upgrade proxy in one step
    function deployAndUpgrade(address proxy, bytes memory implCreationCode) internal returns (address newImpl) {
        newImpl = deployDirect(implCreationCode, bytes(""));
        upgradeProxy(proxy, newImpl);
    }

    // ============================================================
    // Deploy record (deploy.json) read/write
    // ============================================================

    /// @notice Read a deployed address from deployments/deploy.json
    function readDeployment(string memory key) internal view returns (address) {
        (string memory env, string memory chain) = _resolveDeploymentPath();
        return _readDeploymentByPath(env, chain, key);
    }

    /// @notice Read a deployed address for a specific env and chain
    function _readDeploymentByPath(string memory env, string memory chain, string memory key) internal view returns (address addr) {
        string memory filePath = "deployments/deploy.json";
        if (!vm.exists(filePath)) {
            revert(string(abi.encodePacked("deploy.json not found: ", filePath)));
        }
        string memory json = vm.readFile(filePath);
        // JSON path: .prod.Bsc.Gateway
        string memory jsonPath = string(abi.encodePacked(".", env, ".", chain, ".", key));
        addr = json.readAddress(jsonPath);
    }

    /// @notice Save a deployed address to deployments/deploy.json
    function saveDeployment(string memory key, address addr) internal {
        (string memory env, string memory chain) = _resolveDeploymentPath();
        string memory filePath = "deployments/deploy.json";
        // JSON path: .prod.Bsc.Gateway
        string memory jsonPath = string(abi.encodePacked(".", env, ".", chain, ".", key));
        string memory json = vm.readFile(filePath);
        bool exists = vm.keyExistsJson(json, jsonPath);
        if (!exists) {
            revert(string(abi.encodePacked("key not found: ", env, ".", chain, ".", key)));
        }
        vm.writeJson(vm.toString(addr), filePath, jsonPath);
    }

    // ============================================================
    // Internal helpers
    // ============================================================

    /// @notice Resolve deployment path (env, chain) based on chainId and NETWORK_ENV
    /// @return env "prod", "main", or "test"
    /// @return chain "Mapo", "Bsc", etc.
    function _resolveDeploymentPath() internal view returns (string memory env, string memory chain) {
        uint256 chainId = block.chainid;
        env = vm.envString("NETWORK_ENV"); // required: test/prod/main

        if (chainId == 212 || chainId == 22776) chain = "Mapo";
        else if (chainId == 11155111 || chainId == 1) chain = "Eth";
        else if (chainId == 97 || chainId == 56) chain = "Bsc";
        else if (chainId == 8453) chain = "Base";
        else if (chainId == 42161) chain = "Arb";
        else if (chainId == 10) chain = "Op";
        else if (chainId == 130) chain = "Uni";
        else if (chainId == 137) chain = "Pol";
        else if (chainId == 196) chain = "Xlayer";
        else revert("unknown chain");
    }

    /// @notice Read current implementation address from a UUPS proxy
    function _getImplementation(address proxy) internal view returns (address) {
        (bool success, bytes memory data) = proxy.staticcall(
            abi.encodeWithSignature("getImplementation()")
        );
        if (success && data.length == 32) {
            return abi.decode(data, (address));
        }
        return address(0);
    }
}
