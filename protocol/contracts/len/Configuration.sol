// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IConfiguration} from "../interfaces/IConfiguration.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract Configuration is BaseImplementation, IConfiguration {

    // key => keccak256(bytes(key)) => value
    mapping(bytes32 => int256) private intValues;
    mapping(bytes32 => address) private addressValues;
    mapping(bytes32 => bool) private boolValues;
    mapping(bytes32 => string) private stringValues;
    mapping(bytes32 => bytes) private bytesValues;


    event SetIntValue(string key, int256 value);
    event SetAddressValue(string key, address value);
    event SetBoolValue(string key, bool value);
    event SetStringValue(string key, string value);
    event SetBytesValue(string key, bytes value);

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setIntValue(string calldata key, int256 value) external restricted {
        _setIntValue(key, value);
    }

    function batchSetIntValue(string[] calldata keys, int256[] calldata values) external restricted {
        require(keys.length == values.length);
        for (uint256 i = 0; i < keys.length; i++) {
            _setIntValue(keys[i], values[i]);
        }
    }

    function _setIntValue(string calldata key, int256 value) internal {
        bytes memory bytesKey = bytes(key);
        require(bytesKey.length != 0);
        intValues[keccak256(bytesKey)] = value;
        emit SetIntValue(key, value);
    }

    function getIntValue(string calldata key) external view override returns (int256 value) {
        value = intValues[keccak256(bytes(key))];
    }

    function batchGetIntValue(string[] calldata keys) external view returns (int256[] memory values) {
        uint256 length = keys.length;
        values = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = intValues[keccak256(bytes(keys[i]))];
        }
    }

    function setAddressValue(string calldata key, address value) external restricted {
        _setAddressValue(key, value);
    }

    function batchSetAddressValue(string[] calldata keys, address[] calldata values) external restricted {
        uint256 length = keys.length;
        require(length == values.length);
        for (uint256 i = 0; i < length; i++) {
            _setAddressValue(keys[i], values[i]);
        }
    }

    function _setAddressValue(string calldata key, address value) internal {
        bytes memory bytesKey = bytes(key);
        require(bytesKey.length != 0);
        addressValues[keccak256(bytesKey)] = value;
        emit SetAddressValue(key, value);
    }

    function getAddressValue(string calldata key) external view override returns (address value) {
        value = addressValues[keccak256(bytes(key))];
    }
    function batchGetAddressValue(string[] calldata keys) external view returns (address[] memory values) {
        uint256 length = keys.length;
        values = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = addressValues[keccak256(bytes(keys[i]))];
        }
    }

    function setBoolValue(string calldata key, bool value) external restricted {
        _setBoolValue(key, value);
    }

    function batchSetBoolValue(string[] calldata keys, bool[] calldata values) external restricted {
        uint256 length = keys.length;
        require(length == values.length);
        for (uint256 i = 0; i < length; i++) {
            _setBoolValue(keys[i], values[i]);
        }
    }

    function _setBoolValue(string calldata key, bool value) internal {
        bytes memory bytesKey = bytes(key);
        require(bytesKey.length != 0);
        boolValues[keccak256(bytesKey)] = value;
        emit SetBoolValue(key, value);
    }

    function getBoolValue(string calldata key) external view override returns (bool value) {
        value = boolValues[keccak256(bytes(key))];
    }

    function batchGetBoolValue(string[] calldata keys) external view returns (bool[] memory values) {
        uint256 length = keys.length;
        values = new bool[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = boolValues[keccak256(bytes(keys[i]))];
        }
    }

    function setStringValue(string calldata key, string calldata value) external restricted {
        _setStringValue(key, value);
    }

    function batchSetStringValue(string[] calldata keys, string[] calldata values) external restricted {
        uint256 length = keys.length;
        require(length == values.length);
        for (uint256 i = 0; i < length; i++) {
            _setStringValue(keys[i], values[i]);
        }
    }

    function _setStringValue(string calldata key, string calldata value) internal {
        bytes memory bytesKey = bytes(key);
        require(bytesKey.length != 0);
        stringValues[keccak256(bytesKey)] = value;
        emit SetStringValue(key, value);
    }

    function getStringValue(string calldata key) external view override returns (string memory value) {
        value = stringValues[keccak256(bytes(key))];
    }

    function batchGetStringValue(string[] calldata keys) external view returns (string[] memory values) {
        uint256 length = keys.length;
        values = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = stringValues[keccak256(bytes(keys[i]))];
        }
    }

    function setBytesValue(string calldata key, bytes calldata value) external restricted {
        _setBytesValue(key, value);
    }

    function batchSetBytesValue(string[] calldata keys, bytes[] calldata values) external restricted {
        uint256 length = keys.length;
        require(length == values.length);
        for (uint256 i = 0; i < length; i++) {
            _setBytesValue(keys[i], values[i]);
        }
    }

    function _setBytesValue(string calldata key, bytes calldata value) internal {
        bytes memory bytesKey = bytes(key);
        require(bytesKey.length != 0);
        bytesValues[keccak256(bytesKey)] = value;
        emit SetBytesValue(key, value);
    }

    function getBytesValue(string calldata key) external view override returns (bytes memory value) {
        value = bytesValues[keccak256(bytes(key))];
    }

    function batchGetBytesValue(string[] calldata keys) external view returns (bytes[] memory values) {
        uint256 length = keys.length;
        values = new bytes[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = bytesValues[keccak256(bytes(keys[i]))];
        }
    }
   
}
