// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import { IParameters } from "./interfaces/IParameters.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";


contract Parameters is BaseImplementation, IParameters{ 

    event Set(string key, uint256 value);

    
    mapping(bytes32 => uint256) private values;

    function set(string calldata key, uint256 value) external restricted {
        values[keccak256(bytes(key))] = value;
        emit Set(key, value);
    }

    function getByHash(bytes32 hash) external view override returns(uint256 value) {
        value = values[hash];
    }

    function get(string calldata key) external view returns(uint256 value) {
        value = values[keccak256(bytes(key))];
    }

}