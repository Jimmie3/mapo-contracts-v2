// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Constant} from "./libs/Constant.sol";
import {IParameters} from "./interfaces/IParameters.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract Parameters is BaseImplementation, IParameters {
    event Set(string key, uint256 value);

    mapping(bytes32 => uint256) private values;

    function set(string calldata key, uint256 value) external restricted {
        values[keccak256(bytes(key))] = value;
        emit Set(key, value);
    }

    function getByHash(bytes32 hash) external view override returns (uint256 value) {
        value = values[hash];
    }

    function get(string calldata key) external view returns (uint256 value) {
        value = values[keccak256(bytes(key))];
    }

    // uint128 internal constant OBSERVE_MAX_DELAY_BLOCK = 500;
    // uint256 internal constant KEY_GEN_FAIL_JAIL_BLOCK = 100;
    // uint256 internal constant OBSERVE_SLASH_POINT = 2;
    // uint256 internal constant OBSERVE_DELAY_SLASH_POINT = 2;
    // uint256 internal constant KEY_GEN_FAIL_SLASH_POINT = 10;
    // uint256 internal constant KEY_GEN_DELAY_SLASH_POINT = 5;
    // uint256 internal constant MIGRATION_DELAY_SLASH_POINT = 5;
    // uint256 private constant MIN_BLOCKS_PER_EPOCH = 50_000;
    // uint256 private constant MAX_BLOCKS_FO_UPDATE_TSS = 5000;

    function getKeygenFailSlashPoint() external view returns (uint256) {
        return values[Constant.KEY_GEN_DELAY_SLASH_POINT];
    }

}
