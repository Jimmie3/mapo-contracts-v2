// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {ProtocolFee} from "../../contracts/ProtocolFee.sol";
import {IProtocolFee} from "../../contracts/interfaces/periphery/IProtocolFee.sol";
import {ERC1967Proxy} from "../../contracts/ERC1967Proxy.sol";

// Simple ERC20 mock for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ProtocolFeeTest is Test {
    ProtocolFee public protocolFee;
    AccessManager public accessManager;
    MockERC20 public testToken;

    address public admin = address(0x1001);
    address public user1 = address(0x1002);

    // Fee receivers
    address public devReceiver = address(0x2001);
    address public buybackReceiver = address(0x2002);
    address public reserveReceiver = address(0x2003);
    address public stakerReceiver = address(0x2004);

    // FeeType enum values
    IProtocolFee.FeeType constant DEV = IProtocolFee.FeeType.DEV;
    IProtocolFee.FeeType constant BUYBACK = IProtocolFee.FeeType.BUYBACK;
    IProtocolFee.FeeType constant RESERVE = IProtocolFee.FeeType.RESERVE;
    IProtocolFee.FeeType constant STAKER = IProtocolFee.FeeType.STAKER;

    address constant NATIVE_TOKEN = address(0);

    function setUp() public {
        // Deploy AccessManager with admin
        vm.startPrank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ProtocolFee implementation and proxy
        ProtocolFee impl = new ProtocolFee();
        bytes memory initData = abi.encodeCall(ProtocolFee.initialize, (address(accessManager)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        protocolFee = ProtocolFee(payable(address(proxy)));

        vm.stopPrank();

        // Deploy test ERC20 token
        testToken = new MockERC20("Test Token", "TEST");
    }

    // ============================================================
    // Helper: set up default shares and receivers
    // ============================================================

    function _setupSharesAndReceivers() internal {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](4);
        types[0] = DEV;
        types[1] = BUYBACK;
        types[2] = RESERVE;
        types[3] = STAKER;

        uint64[] memory shares = new uint64[](4);
        shares[0] = 60;
        shares[1] = 40;
        shares[2] = 0;
        shares[3] = 0;

        address[] memory receivers = new address[](4);
        receivers[0] = devReceiver;
        receivers[1] = buybackReceiver;
        receivers[2] = reserveReceiver;
        receivers[3] = stakerReceiver;

        vm.startPrank(admin);
        protocolFee.updateShares(types, shares);
        protocolFee.updateReceivers(types, receivers);
        vm.stopPrank();
    }

    // ============================================================
    // Admin / Config tests
    // ============================================================

    function test_updateProtocolFee_setsTotalRate() public {
        vm.prank(admin);
        protocolFee.updateProtocolFee(50000);

        assertEq(protocolFee.totalRate(), 50000);
    }

    function test_updateProtocolFee_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ProtocolFee.UpdateProtocolFee(50000);

        vm.prank(admin);
        protocolFee.updateProtocolFee(50000);
    }

    function test_revert_updateProtocolFee_exceedsMax() public {
        // MAX_TOTAL_RATE is 100_000, so 100_000 should revert (require < not <=)
        vm.prank(admin);
        vm.expectRevert();
        protocolFee.updateProtocolFee(100_000);
    }

    function test_revert_updateProtocolFee_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        protocolFee.updateProtocolFee(50000);
    }

    function test_updateTokens_addsToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        vm.expectEmit(true, false, false, true);
        emit ProtocolFee.UpdateToken(address(testToken), true);

        vm.prank(admin);
        protocolFee.updateTokens(tokens, true);
    }

    function test_updateTokens_removesToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        vm.startPrank(admin);
        // Add first
        protocolFee.updateTokens(tokens, true);

        // Now remove
        vm.expectEmit(true, false, false, true);
        emit ProtocolFee.UpdateToken(address(testToken), false);
        protocolFee.updateTokens(tokens, false);
        vm.stopPrank();
    }

    function test_revert_updateTokens_unauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        vm.prank(user1);
        vm.expectRevert();
        protocolFee.updateTokens(tokens, true);
    }

    function test_updateReceivers_setsReceiverAddress() public {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](1);
        types[0] = DEV;

        address[] memory receivers = new address[](1);
        receivers[0] = devReceiver;

        vm.expectEmit(false, false, false, true);
        emit ProtocolFee.UpdateReceiver(DEV, devReceiver);

        vm.prank(admin);
        protocolFee.updateReceivers(types, receivers);
    }

    function test_revert_updateReceivers_unauthorized() public {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](1);
        types[0] = DEV;
        address[] memory receivers = new address[](1);
        receivers[0] = devReceiver;

        vm.prank(user1);
        vm.expectRevert();
        protocolFee.updateReceivers(types, receivers);
    }

    function test_updateReceivers_lengthMismatch() public {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](2);
        types[0] = DEV;
        types[1] = BUYBACK;
        address[] memory receivers = new address[](1);
        receivers[0] = devReceiver;

        vm.prank(admin);
        vm.expectRevert();
        protocolFee.updateReceivers(types, receivers);
    }

    // ============================================================
    // Share management tests
    // ============================================================

    function test_updateShares_setSharesAndTotalShare() public {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](2);
        types[0] = DEV;
        types[1] = BUYBACK;

        uint64[] memory shares = new uint64[](2);
        shares[0] = 50;
        shares[1] = 30;

        vm.prank(admin);
        protocolFee.updateShares(types, shares);

        assertEq(protocolFee.totalShare(), 80);
    }

    function test_revert_updateShares_unauthorized() public {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](1);
        types[0] = DEV;
        uint64[] memory shares = new uint64[](1);
        shares[0] = 50;

        vm.prank(user1);
        vm.expectRevert();
        protocolFee.updateShares(types, shares);
    }

    function test_revert_updateShares_emptyArrays() public {
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](0);
        uint64[] memory shares = new uint64[](0);

        vm.prank(admin);
        vm.expectRevert();
        protocolFee.updateShares(types, shares);
    }

    function test_revert_updateShares_nonZeroBalance() public {
        // First, register the token and set initial shares
        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](1);
        types[0] = DEV;
        uint64[] memory shares = new uint64[](1);
        shares[0] = 100;

        vm.startPrank(admin);
        protocolFee.updateTokens(tokens, true);
        protocolFee.updateShares(types, shares);
        vm.stopPrank();

        // Send tokens to the contract (simulating fee accumulation)
        testToken.mint(address(protocolFee), 1000e18);

        // Now try to updateShares — should revert because token balance > 0
        IProtocolFee.FeeType[] memory newTypes = new IProtocolFee.FeeType[](1);
        newTypes[0] = DEV;
        uint64[] memory newShares = new uint64[](1);
        newShares[0] = 50;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolFee.invalid_token_balance.selector, address(testToken), 1000e18)
        );
        protocolFee.updateShares(newTypes, newShares);
    }

    // ============================================================
    // Fee calculation tests
    // ============================================================

    function test_getProtocolFee_calculatesCorrectly() public {
        // totalRate = 10000 (1%), amount = 1000e18 => fee = 10e18
        vm.prank(admin);
        protocolFee.updateProtocolFee(10_000);

        uint256 fee = protocolFee.getProtocolFee(address(testToken), 1000e18);
        assertEq(fee, 10e18);
    }

    function test_getProtocolFee_zeroRate() public {
        // totalRate defaults to 0
        uint256 fee = protocolFee.getProtocolFee(address(testToken), 1000e18);
        assertEq(fee, 0);
    }

    // ============================================================
    // Claim flow tests
    // ============================================================

    function test_claim_distributesProportionally() public {
        _setupSharesAndReceivers(); // DEV=60, BUYBACK=40, totalShare=100

        // Send 100e18 testToken to contract
        testToken.mint(address(protocolFee), 100e18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        // Claim DEV share — expect 60e18
        protocolFee.claim(DEV, tokens);
        assertEq(testToken.balanceOf(devReceiver), 60e18);

        // Claim BUYBACK share — expect 40e18
        protocolFee.claim(BUYBACK, tokens);
        assertEq(testToken.balanceOf(buybackReceiver), 40e18);

        // Contract should now have zero balance
        assertEq(testToken.balanceOf(address(protocolFee)), 0);
    }

    function test_claim_nativeToken() public {
        _setupSharesAndReceivers(); // DEV=60, BUYBACK=40

        // Fund contract with 10 ETH
        deal(address(protocolFee), 10 ether);

        address[] memory tokens = new address[](1);
        tokens[0] = NATIVE_TOKEN;

        uint256 devBalanceBefore = devReceiver.balance;

        // Claim DEV share of native token: 60/100 * 10 = 6 ETH
        protocolFee.claim(DEV, tokens);

        assertEq(devReceiver.balance - devBalanceBefore, 6 ether);
    }

    function test_getClaimable_returnsCorrectAmount() public {
        _setupSharesAndReceivers(); // DEV=60, BUYBACK=40, totalShare=100

        testToken.mint(address(protocolFee), 100e18);

        uint256 claimable = protocolFee.getClaimable(DEV, address(testToken));
        assertEq(claimable, 60e18);
    }

    function test_getClaimable_returnsZero_whenTotalShareZero() public {
        // No shares configured — totalShare == 0
        testToken.mint(address(protocolFee), 100e18);

        uint256 claimable = protocolFee.getClaimable(DEV, address(testToken));
        assertEq(claimable, 0);
    }

    function test_getCumulativeFee_tracksAccumulated() public {
        _setupSharesAndReceivers();

        testToken.mint(address(protocolFee), 100e18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        // Before claim: accumulated is 0
        assertEq(protocolFee.getCumulativeFee(DEV, address(testToken)), 0);

        // After claim: accumulated equals claimed amount
        protocolFee.claim(DEV, tokens);
        assertEq(protocolFee.getCumulativeFee(DEV, address(testToken)), 60e18);
    }

    function test_claim_emitsClaimFeeEvent() public {
        _setupSharesAndReceivers();

        testToken.mint(address(protocolFee), 100e18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        vm.expectEmit(false, false, false, true);
        emit ProtocolFee.ClaimFee(DEV, address(testToken), 60e18);

        protocolFee.claim(DEV, tokens);
    }

    function test_claim_noClaimableSkipsTransfer() public {
        _setupSharesAndReceivers();

        // No tokens in contract — claimable == 0, should not revert
        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        // Should not revert, just skip silently
        protocolFee.claim(DEV, tokens);

        // Receiver has no tokens
        assertEq(testToken.balanceOf(devReceiver), 0);
    }

    function test_claim_multipleTokens() public {
        _setupSharesAndReceivers();

        MockERC20 token2 = new MockERC20("Token2", "TK2");
        testToken.mint(address(protocolFee), 100e18);
        token2.mint(address(protocolFee), 200e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(testToken);
        tokens[1] = address(token2);

        protocolFee.claim(DEV, tokens);

        // DEV gets 60% of each token
        assertEq(testToken.balanceOf(devReceiver), 60e18);
        assertEq(token2.balanceOf(devReceiver), 120e18);
    }

    function test_updateShares_overridesExistingShare() public {
        // Set DEV=100
        IProtocolFee.FeeType[] memory types = new IProtocolFee.FeeType[](1);
        types[0] = DEV;
        uint64[] memory shares = new uint64[](1);
        shares[0] = 100;

        vm.prank(admin);
        protocolFee.updateShares(types, shares);
        assertEq(protocolFee.totalShare(), 100);

        // Update DEV=60 — totalShare should update correctly
        shares[0] = 60;
        vm.prank(admin);
        protocolFee.updateShares(types, shares);
        assertEq(protocolFee.totalShare(), 60);
    }
}
