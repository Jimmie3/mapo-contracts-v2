// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Create2Factory
 * @notice Universal CREATE2 factory — works on both EVM and Tron.
 * @dev Address prediction differs between EVM (0xff prefix) and Tron (0x41 prefix).
 *      Use getAddress() on EVM chains, getAddressTron() on Tron.
 *
 * Usage:
 *   // Deploy
 *   bytes32 salt = keccak256("my_salt");
 *   bytes memory code = abi.encodePacked(type(MyContract).creationCode, abi.encode(arg1));
 *   address addr = factory.deploy(salt, code, 0);
 *
 *   // Predict address (off-chain or on-chain)
 *   bytes32 codeHash = keccak256(code);
 *   address predicted = factory.getAddress(salt, codeHash);       // EVM
 *   address predicted = factory.getAddressTron(salt, codeHash);   // Tron
 */
contract Create2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);

    /// @notice Deploy contract via CREATE2
    /// @param salt Deterministic salt
    /// @param creationCode Contract bytecode + constructor args
    /// @param value Native token value to send to the new contract
    /// @return addr The deployed contract address
    function deploy(bytes32 salt, bytes memory creationCode, uint256 value)
        external returns (address addr)
    {
        assembly {
            addr := create2(value, add(creationCode, 0x20), mload(creationCode), salt)
        }
        require(addr != address(0), "DEPLOY_FAILED");
        emit Deployed(addr, salt);
    }

    /// @notice Predict CREATE2 address on EVM chains
    /// @param salt The same salt used in deploy()
    /// @param codeHash keccak256(creationCode) — includes constructor args
    function getAddress(bytes32 salt, bytes32 codeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)
        ))));
    }

    /// @notice Predict CREATE2 address on Tron
    /// @dev Tron uses 0x41 prefix instead of 0xff, and 21-byte sender (41 + 20-byte address)
    /// @param salt The same salt used in deploy()
    /// @param codeHash keccak256(creationCode) — includes constructor args
    function getAddressTron(bytes32 salt, bytes32 codeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0x41), address(this), salt, codeHash)
        ))));
    }
}
