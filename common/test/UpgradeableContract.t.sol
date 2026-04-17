// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/base/BaseImplementation.sol";
import "../contracts/AuthorityManager.sol";
import "./ExampleContract.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract UpgradeableContractTest is Test {
    AuthorityManager public authorityManager;
    ERC1967Proxy public proxy;
    ExampleContract public implementationV1;
    ExampleContractV2 public implementationV2;
    
    address public admin = address(1);
    address public upgrader = address(2);
    address public user = address(3);
    address public unauthorized = address(4);
    
    uint64 public constant UPGRADER_ROLE = 1;
    uint64 public constant USER_ROLE = 2;
    uint32 public constant EXECUTION_DELAY = 0;
    
    event Upgraded(address indexed implementation);
    event ValueSet(uint256 newValue, address setter);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy AuthorityManager
        authorityManager = new AuthorityManager(admin);
        
        // Deploy V1 implementation
        implementationV1 = new ExampleContract();
        
        // Deploy proxy with V1
        bytes memory initData = abi.encodeWithSelector(
            ExampleContract.initialize.selector,
            address(authorityManager)
        );
        proxy = new ERC1967Proxy(address(implementationV1), initData);
        
        // Set up roles
        authorityManager.grantRole(UPGRADER_ROLE, upgrader, EXECUTION_DELAY);
        authorityManager.grantRole(USER_ROLE, user, EXECUTION_DELAY);
        
        // Configure function permissions
        bytes4[] memory upgradeSelectors = new bytes4[](1);
        upgradeSelectors[0] = bytes4(keccak256("upgradeToAndCall(address,bytes)"));
        authorityManager.setTargetFunctionRole(address(proxy), upgradeSelectors, UPGRADER_ROLE);
        
        // Also allow admin to upgrade and use contract functions (admin should have all permissions)
        authorityManager.grantRole(UPGRADER_ROLE, admin, EXECUTION_DELAY);
        authorityManager.grantRole(USER_ROLE, admin, EXECUTION_DELAY);
        
        bytes4[] memory valueSelectors = new bytes4[](2);
        valueSelectors[0] = ExampleContract.setValue.selector;
        valueSelectors[1] = ExampleContract.setBalance.selector;
        authorityManager.setTargetFunctionRole(address(proxy), valueSelectors, USER_ROLE);
        
        vm.stopPrank();
    }
    
    function test_InitialDeployment() public view {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Check proxy is correctly initialized
        assertEq(proxyAsV1.authority(), address(authorityManager));
        assertFalse(proxyAsV1.paused());
        assertEq(proxyAsV1.getImplementation(), address(implementationV1));
        assertEq(proxyAsV1.value(), 100); // Initial value from constructor
        assertEq(proxyAsV1.version(), "1.0.0");
    }
    
    function test_ProxyFunctionality() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Test restricted function with authorized user
        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit ValueSet(500, user);
        proxyAsV1.setValue(500);
        assertEq(proxyAsV1.value(), 500);
        
        // Test unauthorized access
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        proxyAsV1.setValue(600);
    }
    
    function test_UpgradeToV2() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Set some state in V1
        vm.startPrank(user);
        proxyAsV1.setValue(1000);
        proxyAsV1.setBalance(user, 2000);
        vm.stopPrank();
        
        // Deploy V2 implementation
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        // Upgrade to V2
        vm.prank(upgrader);
        bytes memory upgradeData = abi.encodeWithSelector(
            ExampleContractV2.initializeV2.selector,
            "Upgraded Contract",
            1000000
        );
        proxyAsV1.upgradeToAndCall(address(implementationV2), upgradeData);
        
        // Access proxy as V2
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        
        // Verify upgrade
        assertEq(proxyAsV2.getImplementation(), address(implementationV2));
        assertEq(proxyAsV2.version(), "2.0.0");
        
        // Verify state preservation
        assertEq(proxyAsV2.value(), 1000);
        assertEq(proxyAsV2.getBalance(user), 2000);
        
        // Verify new state initialized
        assertEq(proxyAsV2.name(), "Upgraded Contract");
        assertEq(proxyAsV2.totalSupply(), 1000000);
    }
    
    function test_UpgradePermissions() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        // Admin can upgrade (has ADMIN_ROLE)
        vm.prank(admin);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        // Reset to V1
        vm.prank(admin);
        ExampleContractV2(address(proxy)).upgradeToAndCall(address(implementationV1), "");
        
        // Authorized upgrader can upgrade
        vm.prank(upgrader);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        // Reset to V1
        vm.prank(admin);
        ExampleContractV2(address(proxy)).upgradeToAndCall(address(implementationV1), "");
        
        // Unauthorized user cannot upgrade
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
    }
    
    function test_V2NewFunctionality() public {
        // Upgrade to V2
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        vm.prank(upgrader);
        ExampleContract(address(proxy)).upgradeToAndCall(address(implementationV2), "");
        
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        
        // Set up permissions for new functions
        vm.startPrank(admin);
        bytes4[] memory nameSelectors = new bytes4[](1);
        nameSelectors[0] = ExampleContractV2.setName.selector;
        authorityManager.setTargetFunctionRole(address(proxy), nameSelectors, USER_ROLE);
        
        bytes4[] memory supplySelectors = new bytes4[](1);
        supplySelectors[0] = ExampleContractV2.setTotalSupply.selector;
        authorityManager.setTargetFunctionRole(address(proxy), supplySelectors, USER_ROLE);
        vm.stopPrank();
        
        // Test new functionality
        vm.prank(user);
        proxyAsV2.setName("New Name");
        assertEq(proxyAsV2.name(), "New Name");
        
        vm.prank(user);
        proxyAsV2.setTotalSupply(5000000);
        assertEq(proxyAsV2.totalSupply(), 5000000);
        
        // Test unauthorized access to new functions
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        proxyAsV2.setName("Unauthorized Name");
    }
    
    function test_StatePreservationAcrossUpgrade() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Set complex state in V1 (admin can call any function)
        vm.startPrank(admin);
        proxyAsV1.setValue(12345);
        proxyAsV1.setBalance(admin, 11111);
        proxyAsV1.setBalance(user, 22222);
        proxyAsV1.setBalance(upgrader, 33333);
        vm.stopPrank();
        
        // Pause the contract
        vm.prank(admin);
        proxyAsV1.trigger();
        assertTrue(proxyAsV1.paused());
        
        // Upgrade to V2
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        vm.prank(upgrader);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        
        // Verify all state is preserved
        assertEq(proxyAsV2.value(), 12345);
        assertEq(proxyAsV2.getBalance(admin), 11111);
        assertEq(proxyAsV2.getBalance(user), 22222);
        assertEq(proxyAsV2.getBalance(upgrader), 33333);
        assertTrue(proxyAsV2.paused());
        
        // Verify authority is preserved
        assertEq(proxyAsV2.authority(), address(authorityManager));
    }
    
    function test_UpgradeWithoutReinitialize() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Set initial state
        vm.prank(user);
        proxyAsV1.setValue(999);
        
        // Upgrade without calling initializeV2
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        vm.prank(upgrader);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        
        // Old state preserved
        assertEq(proxyAsV2.value(), 999);
        assertEq(proxyAsV2.version(), "2.0.0");
        
        // New fields have default values
        assertEq(proxyAsV2.name(), "");
        assertEq(proxyAsV2.totalSupply(), 0);
        
        // Can initialize V2 later
        vm.prank(admin);
        proxyAsV2.initializeV2("Late Init", 777777);
        
        assertEq(proxyAsV2.name(), "Late Init");
        assertEq(proxyAsV2.totalSupply(), 777777);
    }
    
    function test_MultipleUpgradeSequence() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Set initial state
        vm.prank(user);
        proxyAsV1.setValue(100);
        
        // First upgrade: V1 -> V2
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        vm.prank(upgrader);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        assertEq(proxyAsV2.version(), "2.0.0");
        assertEq(proxyAsV2.value(), 100);
        
        // Set V2-specific state
        vm.prank(admin);
        proxyAsV2.initializeV2("V2 Contract", 50000);
        
        // Second upgrade: V2 -> V1 (downgrade)
        vm.prank(admin);
        ExampleContract newV1Implementation = new ExampleContract();
        
        vm.prank(upgrader);
        proxyAsV2.upgradeToAndCall(address(newV1Implementation), "");
        
        ExampleContract downgradedProxy = ExampleContract(address(proxy));
        
        // Version should be back to V1
        assertEq(downgradedProxy.version(), "1.0.0");
        
        // Common state should be preserved
        assertEq(downgradedProxy.value(), 100);
        
        // V2-specific data is lost (no longer accessible through V1 interface)
        // But the storage slots still contain the data
    }
    
    function test_UpgradeFailureCases() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Cannot upgrade to zero address
        vm.prank(admin);
        vm.expectRevert();
        proxyAsV1.upgradeToAndCall(address(0), "");
        
        // Cannot upgrade to non-contract address
        vm.prank(admin);
        vm.expectRevert();
        proxyAsV1.upgradeToAndCall(user, "");
        
        // Cannot upgrade with invalid initialization data
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        bytes memory badInitData = abi.encodeWithSelector(
            bytes4(keccak256("nonExistentFunction()")),
            ""
        );
        
        vm.prank(admin);
        vm.expectRevert();
        proxyAsV1.upgradeToAndCall(address(implementationV2), badInitData);
    }
    
    function test_AuthorityChangeAfterUpgrade() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Create new authority manager
        vm.prank(admin);
        AuthorityManager newAuthorityManager = new AuthorityManager(admin);
        
        // Change authority
        vm.prank(admin);
        authorityManager.updateAuthority(address(proxy), address(newAuthorityManager));
        
        // Verify authority changed
        assertEq(proxyAsV1.authority(), address(newAuthorityManager));
        
        // Upgrade should still work with new authority
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        // Set upgrade permission in new authority
        vm.startPrank(admin);
        newAuthorityManager.grantRole(UPGRADER_ROLE, upgrader, EXECUTION_DELAY);
        bytes4[] memory upgradeSelectors = new bytes4[](1);
        upgradeSelectors[0] = bytes4(keccak256("upgradeToAndCall(address,bytes)"));
        newAuthorityManager.setTargetFunctionRole(address(proxy), upgradeSelectors, UPGRADER_ROLE);
        vm.stopPrank();
        
        // Upgrade should work
        vm.prank(upgrader);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        assertEq(proxyAsV2.authority(), address(newAuthorityManager));
        assertEq(proxyAsV2.version(), "2.0.0");
    }
    
    function test_PauseAndUpgrade() public {
        ExampleContract proxyAsV1 = ExampleContract(address(proxy));
        
        // Pause the contract
        vm.prank(admin);
        proxyAsV1.trigger();
        assertTrue(proxyAsV1.paused());
        
        // Should still be able to upgrade when paused (upgrade is restricted, not pausable)
        vm.prank(admin);
        implementationV2 = new ExampleContractV2();
        
        vm.prank(upgrader);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");
        
        ExampleContractV2 proxyAsV2 = ExampleContractV2(address(proxy));
        
        // Should still be paused after upgrade
        assertTrue(proxyAsV2.paused());
        
        // Should be able to unpause
        vm.prank(admin);
        proxyAsV2.trigger();
        assertFalse(proxyAsV2.paused());
    }
}