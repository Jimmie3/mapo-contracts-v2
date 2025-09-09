// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constant {

    bytes32 internal constant OBSERVE_MAX_DELAY_BLOCK = keccak256(bytes("OBSERVE_MAX_DELAY_BLOCK"));
    bytes32 internal constant KEY_GEN_FAIL_JAIL_BLOCK = keccak256(bytes("KEY_GEN_FAIL_JAIL_BLOCK"));
    // KEY_GEN_DELAY_SLASH_POINT must gt MAX_SLASH_POINT_FOR_ELECT
    // It means that if there is a KEY_GEN_DELAY, they cannot be elected in the next election.
    bytes32 internal constant MIGRATION_DELAY_JAIL_BLOCK = keccak256(bytes("MIGRATION_DELAY_JAIL_BLOCK"));
    bytes32 internal constant OBSERVE_SLASH_POINT = keccak256(bytes("OBSERVE_SLASH_POINT"));
    bytes32 internal constant OBSERVE_DELAY_SLASH_POINT = keccak256(bytes("OBSERVE_DELAY_SLASH_POINT"));
    bytes32 internal constant KEY_GEN_FAIL_SLASH_POINT = keccak256(bytes("KEY_GEN_FAIL_SLASH_POINT"));
    bytes32 internal constant KEY_GEN_DELAY_SLASH_POINT = keccak256(bytes("KEY_GEN_DELAY_SLASH_POINT"));
    bytes32 internal constant MIGRATION_DELAY_SLASH_POINT = keccak256(bytes("MIGRATION_DELAY_SLASH_POINT"));
    bytes32 internal constant MIN_BLOCKS_PER_EPOCH = keccak256(bytes("MIN_BLOCKS_PER_EPOCH"));
    bytes32 internal constant MAX_BLOCKS_FOR_UPDATE_TSS = keccak256(bytes("MAX_BLOCKS_FO_UPDATE_TSS"));
}
