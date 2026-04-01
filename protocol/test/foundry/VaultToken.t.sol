// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";

import {VaultToken} from "../../contracts/VaultToken.sol";
import {ERC1967Proxy} from "../../contracts/ERC1967Proxy.sol";

contract VaultTokenTest is BaseTest {
    VaultToken public vaultToken;

    uint256 constant DEPOSIT_AMOUNT = 100e18;

    function setUp() public override {
        super.setUp();

        // Deploy VaultToken impl + proxy for testToken (same pattern as VaultManagerTest)
        address vaultTokenImpl = address(new VaultToken());
        address vaultTokenProxy = _deployProxy(
            vaultTokenImpl,
            abi.encodeCall(VaultToken.initialize, (address(authority), address(testToken), "Vault Test Token", "vTT"))
        );
        vaultToken = VaultToken(vaultTokenProxy);

        // Set vaultManager on the token (restricted = admin role)
        vm.prank(admin);
        vaultToken.setVaultManager(address(vaultManager));

        // Register the token in VaultManager so it's fully wired
        vm.prank(admin);
        vaultManager.registerToken(address(testToken), address(vaultToken));
    }

    // -----------------------------------------------------------------------
    // Initialization
    // -----------------------------------------------------------------------

    function test_initialize_setsAssetAndName() public view {
        assertEq(vaultToken.asset(), address(testToken));
        assertEq(vaultToken.name(), "Vault Test Token");
        assertEq(vaultToken.symbol(), "vTT");
    }

    function test_initialize_setsAuthority() public view {
        // Contract should not be paused after initialization
        assertFalse(vaultToken.paused());
        // authority() returns the access manager address
        assertEq(vaultToken.authority(), address(authority));
    }

    // -----------------------------------------------------------------------
    // setVaultManager
    // -----------------------------------------------------------------------

    function test_setVaultManager_updatesManager() public {
        address newManager = makeAddr("newManager");
        vm.prank(admin);
        vaultToken.setVaultManager(newManager);
        assertEq(vaultToken.vaultManager(), newManager);
    }

    function test_setVaultManager_emitsEvent() public {
        address newManager = makeAddr("newManager");
        vm.expectEmit(true, false, false, false, address(vaultToken));
        emit VaultToken.VaultManagerSet(newManager);
        vm.prank(admin);
        vaultToken.setVaultManager(newManager);
    }

    function test_revert_setVaultManager_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultToken.setVaultManager(makeAddr("x"));
    }

    // -----------------------------------------------------------------------
    // increaseVault
    // -----------------------------------------------------------------------

    function test_increaseVault_updatesBalance() public {
        vm.prank(address(vaultManager));
        vaultToken.increaseVault(DEPOSIT_AMOUNT);
        assertEq(vaultToken.balance(), DEPOSIT_AMOUNT);
    }

    function test_increaseVault_emitsVaultIncreased() public {
        vm.expectEmit(true, false, false, true, address(vaultToken));
        emit VaultToken.VaultIncreased(address(testToken), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        vm.prank(address(vaultManager));
        vaultToken.increaseVault(DEPOSIT_AMOUNT);
    }

    function test_revert_increaseVault_notManager() public {
        vm.prank(user1);
        vm.expectRevert(VaultToken.only_manager_role.selector);
        vaultToken.increaseVault(DEPOSIT_AMOUNT);
    }

    // -----------------------------------------------------------------------
    // decreaseVault
    // -----------------------------------------------------------------------

    function test_decreaseVault_updatesBalance() public {
        vm.prank(address(vaultManager));
        vaultToken.increaseVault(DEPOSIT_AMOUNT);

        vm.prank(address(vaultManager));
        vaultToken.decreaseVault(40e18);

        assertEq(vaultToken.balance(), 60e18);
    }

    function test_decreaseVault_emitsVaultDecreased() public {
        vm.prank(address(vaultManager));
        vaultToken.increaseVault(DEPOSIT_AMOUNT);

        vm.expectEmit(true, false, false, true, address(vaultToken));
        emit VaultToken.VaultDecreased(address(testToken), 40e18, 60e18);
        vm.prank(address(vaultManager));
        vaultToken.decreaseVault(40e18);
    }

    function test_revert_decreaseVault_notManager() public {
        vm.prank(user1);
        vm.expectRevert(VaultToken.only_manager_role.selector);
        vaultToken.decreaseVault(1e18);
    }

    // -----------------------------------------------------------------------
    // totalAssets
    // -----------------------------------------------------------------------

    function test_totalAssets_returnsBalance() public {
        assertEq(vaultToken.totalAssets(), 0);

        vm.prank(address(vaultManager));
        vaultToken.increaseVault(DEPOSIT_AMOUNT);

        assertEq(vaultToken.totalAssets(), DEPOSIT_AMOUNT);
    }

    // -----------------------------------------------------------------------
    // deposit (ERC4626) — only callable from vaultManager
    // -----------------------------------------------------------------------

    function test_deposit_mintsShares_onlyViaManager() public {
        // With empty vault (totalAssets=0, totalSupply=0), ERC4626 mints 1:1
        // deposit() triggers _deposit() which checks caller == vaultManager
        vm.startPrank(address(vaultManager));
        uint256 sharesBefore = vaultToken.balanceOf(user1);
        vaultToken.deposit(DEPOSIT_AMOUNT, user1);
        uint256 sharesAfter = vaultToken.balanceOf(user1);

        assertGt(sharesAfter, sharesBefore);
        // _deposit updates balance: += assets
        assertEq(vaultToken.balance(), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_revert_deposit_notManager() public {
        vm.prank(user1);
        vm.expectRevert(VaultToken.only_manager_role.selector);
        vaultToken.deposit(DEPOSIT_AMOUNT, user1);
    }

    // -----------------------------------------------------------------------
    // withdraw (ERC4626) — only callable from vaultManager
    // -----------------------------------------------------------------------

    function test_withdraw_burnsShares_onlyViaManager() public {
        // Setup: deposit to user1 via vaultManager (1:1, so user1 gets DEPOSIT_AMOUNT shares)
        vm.startPrank(address(vaultManager));
        vaultToken.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 sharesBefore = vaultToken.balanceOf(user1);
        uint256 balanceBefore = vaultToken.balance();
        assertEq(sharesBefore, DEPOSIT_AMOUNT);

        // withdraw() triggers _withdraw() which checks caller == vaultManager
        vm.prank(address(vaultManager));
        vaultToken.withdraw(DEPOSIT_AMOUNT, user1, user1);

        assertLt(vaultToken.balanceOf(user1), sharesBefore);
        assertLt(vaultToken.balance(), balanceBefore);
    }

    function test_revert_withdraw_notManager() public {
        // Setup: deposit shares to user1 first so ERC4626 max check passes
        vm.prank(address(vaultManager));
        vaultToken.deposit(DEPOSIT_AMOUNT, user1);

        // user1 tries to withdraw directly — _withdraw checks caller == vaultManager
        vm.prank(user1);
        vm.expectRevert(VaultToken.only_manager_role.selector);
        vaultToken.withdraw(DEPOSIT_AMOUNT, user1, user1);
    }

    // -----------------------------------------------------------------------
    // previewDeposit / previewRedeem math
    // -----------------------------------------------------------------------

    function test_previewDeposit_returnsExpectedShares() public {
        // With empty vault (totalAssets == 0, totalSupply == 0), ERC4626 mints 1:1
        uint256 preview = vaultToken.previewDeposit(DEPOSIT_AMOUNT);
        assertEq(preview, DEPOSIT_AMOUNT);
    }

    function test_previewDeposit_withExistingSupply() public {
        // Step 1: deposit 100e18 at 1:1 -> totalAssets=100e18, totalSupply=100e18
        // Step 2: increaseVault(100e18) -> totalAssets=200e18, totalSupply=100e18
        // previewDeposit(100e18) = 100e18 * (100e18+1) / (200e18+1) ≈ 50e18
        vm.startPrank(address(vaultManager));
        vaultToken.deposit(DEPOSIT_AMOUNT, user1);
        vaultToken.increaseVault(DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 preview = vaultToken.previewDeposit(DEPOSIT_AMOUNT);
        // Due to ERC4626 virtual shares offset (+1 on both sides), result is slightly under 50e18
        assertApproxEqAbs(preview, 50e18, 1);
    }

    function test_previewRedeem_returnsExpectedAssets() public {
        // With empty vault (1:1), 100 shares == 100 assets
        uint256 preview = vaultToken.previewRedeem(DEPOSIT_AMOUNT);
        assertEq(preview, DEPOSIT_AMOUNT);
    }

    function test_previewRedeem_withExistingSupply() public {
        // Step 1: deposit 100e18 at 1:1 -> totalAssets=100e18, totalSupply=100e18
        // Step 2: increaseVault(100e18) -> totalAssets=200e18, totalSupply=100e18
        // previewRedeem(50 shares) = 50e18 * (200e18+1) / (100e18+1) ≈ 100e18
        vm.startPrank(address(vaultManager));
        vaultToken.deposit(DEPOSIT_AMOUNT, user1);
        vaultToken.increaseVault(DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 preview = vaultToken.previewRedeem(50e18);
        assertApproxEqAbs(preview, DEPOSIT_AMOUNT, 1);
    }
}
