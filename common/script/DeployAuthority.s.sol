// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Script.sol";
import {BaseScript} from "./base/Base.s.sol";
import {AuthorityManager} from "../contracts/AuthorityManager.sol";

/**
 * @title DeployAuthority
 * @notice Deploy AuthorityManager with optional factory (CREATE2) support
 *
 * Usage:
 *   # Direct deploy
 *   forge script script/DeployAuthority.s.sol:DeployAuthority \
 *     --rpc-url Bsc --broadcast --verify
 *
 *   # Factory deploy (deterministic address)
 *   AUTHORITY_SALT=mapo_authority forge script script/DeployAuthority.s.sol:DeployAuthority \
 *     --sig "deployWithFactory()" --rpc-url Bsc --broadcast --verify
 */
contract DeployAuthority is BaseScript {

    function run() public broadcast {
        console.log("Deployer:", broadcaster);
        console.log("Chain ID:", block.chainid);

        AuthorityManager authority = new AuthorityManager(broadcaster);
        console.log("AuthorityManager deployed:", address(authority));
        _verify(authority);
    }

    function deployWithFactory() public broadcast {
        string memory salt = vm.envString("AUTHORITY_SALT");
        console.log("Deployer:", broadcaster);
        console.log("Chain ID:", block.chainid);
        console.log("Salt:", salt);

        if (isFactoryDeployed(salt)) {
            console.log("Already deployed at:", getFactoryAddress(salt));
            return;
        }

        address addr = deployByFactory(
            salt,
            type(AuthorityManager).creationCode,
            abi.encode(broadcaster)
        );
        console.log("AuthorityManager deployed:", addr);

        _verify(AuthorityManager(addr));
    }

    function _verify(AuthorityManager authority) internal view {
        uint256 adminCount = authority.getRoleMemberCount(authority.ADMIN_ROLE());
        console.log("Admin members:", adminCount);
        if (adminCount > 0) {
            console.log("First admin:", authority.getRoleMember(authority.ADMIN_ROLE(), 0));
        }
    }
}
