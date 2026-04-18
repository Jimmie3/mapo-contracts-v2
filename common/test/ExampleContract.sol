// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/base/BaseImplementation.sol";

/**
 * @title ExampleContract
 * @notice Example V1 contract demonstrating BaseImplementation usage
 */
contract ExampleContract is BaseImplementation {
    uint256 public value;
    mapping(address => uint256) private _balances;

    event ValueSet(uint256 newValue, address setter);

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
        value = 100;
    }

    function version() public pure virtual returns (string memory) {
        return "1.0.0";
    }

    function setValue(uint256 _value) public restricted {
        value = _value;
        emit ValueSet(_value, msg.sender);
    }

    function setBalance(address account, uint256 amount) public restricted {
        _balances[account] = amount;
    }

    function getBalance(address account) public view returns (uint256) {
        return _balances[account];
    }
}

/**
 * @title ExampleContractV2
 * @notice Example V2 contract demonstrating upgrade with new storage
 */
contract ExampleContractV2 is ExampleContract {
    string public name;
    uint256 public totalSupply;

    function initializeV2(string memory _name, uint256 _totalSupply) public reinitializer(2) {
        name = _name;
        totalSupply = _totalSupply;
    }

    function version() public pure override returns (string memory) {
        return "2.0.0";
    }

    function setName(string memory _name) public restricted {
        name = _name;
    }

    function setTotalSupply(uint256 _totalSupply) public restricted {
        totalSupply = _totalSupply;
    }
}
