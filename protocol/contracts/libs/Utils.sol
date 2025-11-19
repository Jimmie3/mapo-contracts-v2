// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {


    function bytesEq(bytes memory b1, bytes memory b2) internal pure returns (bool) {
        return keccak256(b1) == keccak256(b2);
    }


    function fromBytes(bytes memory bys) internal pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function toBytes(address self) internal pure returns (bytes memory b) {
        b = abi.encodePacked(self);
    }

    function getAddressFromPublicKey(bytes memory publicKey) internal pure returns (address) {
        return address(uint160(uint256(keccak256(publicKey))));
    }

    function getVaultKey(bytes memory publicKey) internal pure returns (bytes32) {
        return keccak256(publicKey);
    }
}
