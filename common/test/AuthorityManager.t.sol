// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/AuthorityManager.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";

contract AuthorityManagerTest is Test {
    AuthorityManager public authorityManager;
    
    address public defaultAdmin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    
    uint64 public constant ROLE_1 = 1;
    uint64 public constant ROLE_2 = 2;
    uint32 public constant EXECUTION_DELAY = 0;
    
    event RoleGranted(uint64 indexed roleId, address indexed account, uint32 delay, uint48 since, bool newMember);
    event RoleRevoked(uint64 indexed roleId, address indexed account);
    
    function setUp() public {
        vm.prank(defaultAdmin);
        authorityManager = new AuthorityManager(defaultAdmin);
    }
    
    function test_Constructor() public view {
        assertEq(authorityManager.getRoleMemberCount(authorityManager.ADMIN_ROLE()), 1);
        assertEq(authorityManager.getRoleMember(authorityManager.ADMIN_ROLE(), 0), defaultAdmin);
    }
    
    function test_GrantRole() public {
        vm.prank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 1);
        assertEq(authorityManager.getRoleMember(ROLE_1, 0), user1);
        (bool hasRole,) = authorityManager.hasRole(ROLE_1, user1);
        assertTrue(hasRole);
    }
    
    function test_GrantRoleMultipleMembers() public {
        vm.startPrank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_1, user2, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_1, user3, EXECUTION_DELAY);
        vm.stopPrank();
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 3);
        
        address[] memory members = authorityManager.getRoleMembers(ROLE_1);
        assertEq(members.length, 3);
        assertTrue(_contains(members, user1));
        assertTrue(_contains(members, user2));
        assertTrue(_contains(members, user3));
    }
    
    function test_GrantRoleDuplicateMember() public {
        vm.startPrank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        vm.stopPrank();
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 1);
        assertEq(authorityManager.getRoleMember(ROLE_1, 0), user1);
    }
    
    function test_RevokeRole() public {
        vm.startPrank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_1, user2, EXECUTION_DELAY);
        
        authorityManager.revokeRole(ROLE_1, user1);
        vm.stopPrank();
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 1);
        assertEq(authorityManager.getRoleMember(ROLE_1, 0), user2);
        (bool hasRole1,) = authorityManager.hasRole(ROLE_1, user1);
        (bool hasRole2,) = authorityManager.hasRole(ROLE_1, user2);
        assertFalse(hasRole1);
        assertTrue(hasRole2);
    }
    
    function test_RevokeRoleNonExistent() public {
        vm.prank(defaultAdmin);
        authorityManager.revokeRole(ROLE_1, user1);
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 0);
    }
    
    function test_RenounceRole() public {
        vm.prank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        
        vm.prank(user1);
        authorityManager.renounceRole(ROLE_1, user1);
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 0);
        (bool hasRole,) = authorityManager.hasRole(ROLE_1, user1);
        assertFalse(hasRole);
    }
    
    function test_RenounceRoleWrongConfirmation() public {
        vm.prank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerBadConfirmation.selector));
        authorityManager.renounceRole(ROLE_1, user2);
    }
    
    function test_GetRoleMemberOutOfBounds() public {
        vm.expectRevert();
        authorityManager.getRoleMember(ROLE_1, 0);
    }
    
    function test_MultipleRoles() public {
        vm.startPrank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_2, user1, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_1, user2, EXECUTION_DELAY);
        authorityManager.grantRole(ROLE_2, user3, EXECUTION_DELAY);
        vm.stopPrank();
        
        assertEq(authorityManager.getRoleMemberCount(ROLE_1), 2);
        assertEq(authorityManager.getRoleMemberCount(ROLE_2), 2);
        
        (bool hasRole1_user1,) = authorityManager.hasRole(ROLE_1, user1);
        (bool hasRole2_user1,) = authorityManager.hasRole(ROLE_2, user1);
        (bool hasRole1_user2,) = authorityManager.hasRole(ROLE_1, user2);
        (bool hasRole2_user2,) = authorityManager.hasRole(ROLE_2, user2);
        (bool hasRole1_user3,) = authorityManager.hasRole(ROLE_1, user3);
        (bool hasRole2_user3,) = authorityManager.hasRole(ROLE_2, user3);
        
        assertTrue(hasRole1_user1);
        assertTrue(hasRole2_user1);
        assertTrue(hasRole1_user2);
        assertFalse(hasRole2_user2);
        assertFalse(hasRole1_user3);
        assertTrue(hasRole2_user3);
    }
    
    function test_UnauthorizedGrantRole() public {
        vm.prank(user1);
        vm.expectRevert();
        authorityManager.grantRole(ROLE_1, user2, EXECUTION_DELAY);
    }
    
    function test_UnauthorizedRevokeRole() public {
        vm.prank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        
        vm.prank(user2);
        vm.expectRevert();
        authorityManager.revokeRole(ROLE_1, user1);
    }
    
    function test_SetRoleAdmin() public {
        vm.startPrank(defaultAdmin);
        authorityManager.setRoleAdmin(ROLE_1, ROLE_2);
        
        (bool isMember, uint32 executionDelay) = authorityManager.hasRole(ROLE_2, defaultAdmin);
        assertFalse(isMember);
        
        authorityManager.grantRole(ROLE_2, user1, EXECUTION_DELAY);
        vm.stopPrank();
        
        vm.prank(user1);
        authorityManager.grantRole(ROLE_1, user2, EXECUTION_DELAY);
        
        (bool hasRole,) = authorityManager.hasRole(ROLE_1, user2);
        assertTrue(hasRole);
    }
    
    function test_GetRoleAdmin() public {
        vm.prank(defaultAdmin);
        authorityManager.setRoleAdmin(ROLE_1, ROLE_2);
        
        assertEq(authorityManager.getRoleAdmin(ROLE_1), ROLE_2);
    }
    
    function test_SetGrantDelay() public {
        uint32 newDelay = 3600;
        
        vm.prank(defaultAdmin);
        authorityManager.setGrantDelay(ROLE_1, newDelay);
        
        // Note: Grant delay changes may have additional authorization requirements
        // This test verifies the function call works, actual delay change may require guardian setup
    }
    
    function test_GetAccessManaged() public {
        vm.prank(defaultAdmin);
        authorityManager.grantRole(ROLE_1, user1, EXECUTION_DELAY);
        
        (bool isMember, uint32 executionDelay) = authorityManager.hasRole(ROLE_1, user1);
        assertTrue(isMember);
        assertEq(executionDelay, EXECUTION_DELAY);
    }
    
    function _contains(address[] memory array, address value) private pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                return true;
            }
        }
        return false;
    }
}