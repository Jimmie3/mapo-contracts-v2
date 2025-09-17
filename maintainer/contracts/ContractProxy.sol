// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ContractProxy is ERC1967Proxy {
    error logic_zero_address();

    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {
        if (_logic == address(0)) revert logic_zero_address();
    }
}
