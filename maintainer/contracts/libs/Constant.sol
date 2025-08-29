// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constant {
    uint128 internal constant MAX_DELYA_BLOCK = 500;
    uint256 internal constant JAIL_SLASH_LIMIT = 100;
    uint256 internal constant VOTE_TX_SCORE = 3;
    uint256 internal constant VOTE_TX_DELAY_SCORE = 1;
    uint256 internal constant OBSERVE_SLASH_POINT = 2;
    uint256 internal constant OBSERVE_DELAY_SLASH_POINT = 2;
    uint256 internal constant KEY_GEN_FAIL_SLASH_POINT = 10;
    uint256 internal constant KEY_GEN_DELAY_SLASY_POINT = 5;
    uint256 internal constant MIGRATION_DELAY_SLASH_POINT = 5;  
}