// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/**
 * @title BaseScript
 * @notice Base contract for deployment scripts with factory deploy and upgrade support
 * @dev Inherit this in your deployment scripts for common functionality
 *
 * Features:
 *   - Private key management (mainnet / testnet)
 *   - Factory (CREATE2) deployment for deterministic addresses
 *   - Proxy deployment (ERC1967)
 *   - Contract upgrade helper
 */
abstract contract BaseScript is Script {
    IFactory constant private FACTORY = IFactory(0x6258e4d2950757A749a4d4683A7342261ce12471);

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
    /// @param salt Human-readable salt string
    /// @param creationCode Contract creation code (type(X).creationCode)
    /// @param constructorArgs ABI-encoded constructor arguments
    /// @return addr The deployed contract address
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
    /// @dev Override this if you need custom deployment logic
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

    // ============================================================
    // Upgrade
    // ============================================================

    /// @notice Upgrade a UUPS proxy to a new implementation
    /// @param proxy The proxy contract address
    /// @param newImpl The new implementation address
    function upgradeProxy(address proxy, address newImpl) internal {
        (bool success,) = proxy.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, bytes(""))
        );
        require(success, "upgrade failed");
        console.log("Upgraded proxy:", proxy);
        console.log("New implementation:", newImpl);
    }

    /// @notice Deploy new implementation and upgrade proxy in one step
    /// @param proxy The proxy contract address
    /// @param creationCode New implementation creation code
    function deployAndUpgrade(address proxy, bytes memory creationCode) internal returns (address newImpl) {
        newImpl = deployDirect(creationCode, bytes(""));
        upgradeProxy(proxy, newImpl);
    }
}
