// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";

contract GasServiceTest is BaseTest {
    // Values used when posting a fee
    uint256 constant HEIGHT = 100;
    uint256 constant TX_SIZE = 200;        // bytes (not scaled)
    uint256 constant TX_SIZE_WITH_CALL = 300; // bytes for calls with payload
    uint256 constant TX_RATE = 1000;       // rate per byte

    // -----------------------------------------------------------------------
    // Initialization / setRegistry
    // -----------------------------------------------------------------------

    function test_initialize_setsAuthority() public view {
        assertEq(gasService.authority(), address(authority));
    }

    function test_setRegistry_updatesRegistry() public {
        address newRegistry = makeAddr("newRegistry");
        vm.prank(admin);
        gasService.setRegistry(newRegistry);
        assertEq(address(gasService.registry()), newRegistry);
    }

    // -----------------------------------------------------------------------
    // postNetworkFee — access control
    // -----------------------------------------------------------------------

    /// @dev Happy path: only the address registered as ContractType.RELAY can post fees.
    ///      BaseTest registers address(relay) as ContractType.RELAY, so we prank as relay.
    function test_postNetworkFee_storesFee() public {
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        // getNetworkFee applies a 1.5x multiplier to transactionRate
        // fee = transactionSize * (transactionRate * 3 / 2)
        uint256 expectedFeeWithoutCall = TX_SIZE * ((TX_RATE * 3) / 2);
        uint256 expectedFeeWithCall = TX_SIZE_WITH_CALL * ((TX_RATE * 3) / 2);

        assertEq(gasService.getNetworkFee(ETH_CHAIN_ID, false), expectedFeeWithoutCall);
        assertEq(gasService.getNetworkFee(ETH_CHAIN_ID, true), expectedFeeWithCall);
    }

    function test_postNetworkFee_updatesExistingFee() public {
        // Post initial fee
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        // Update with new values
        uint256 newRate = 2000;
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT + 10, TX_SIZE + 50, TX_SIZE_WITH_CALL + 50, newRate);

        uint256 expected = (TX_SIZE + 50) * ((newRate * 3) / 2);
        assertEq(gasService.getNetworkFee(ETH_CHAIN_ID, false), expected);
    }

    /// @dev user1 is not the relay — should revert
    function test_revert_postNetworkFee_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);
    }

    /// @dev mockTssManager is registered as ContractType.TSS_MANAGER, NOT ContractType.RELAY
    ///      postNetworkFee requires ContractType.RELAY — so TSS_MANAGER should be rejected
    function test_revert_postNetworkFee_unauthorizedTssManager() public {
        vm.prank(mockTssManager);
        vm.expectRevert();
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);
    }

    // -----------------------------------------------------------------------
    // getNetworkFee — variants
    // -----------------------------------------------------------------------

    function test_getNetworkFee_withCallFalse() public {
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        uint256 fee = gasService.getNetworkFee(ETH_CHAIN_ID, false);
        uint256 expected = TX_SIZE * ((TX_RATE * 3) / 2);
        assertEq(fee, expected);
    }

    function test_getNetworkFee_withCallTrue() public {
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        uint256 fee = gasService.getNetworkFee(ETH_CHAIN_ID, true);
        uint256 expected = TX_SIZE_WITH_CALL * ((TX_RATE * 3) / 2);
        assertEq(fee, expected);
    }

    function test_getNetworkFee_unregisteredChain_returnsZero() public view {
        uint256 fee = gasService.getNetworkFee(99999, false);
        assertEq(fee, 0);
    }

    // -----------------------------------------------------------------------
    // getNetworkFeeInfo — overloads
    // -----------------------------------------------------------------------

    function test_getNetworkFeeInfo_returnsAllFields() public {
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        (uint256 networkFee, uint256 transactionRate, uint256 transactionSize) =
            gasService.getNetworkFeeInfo(ETH_CHAIN_ID, false);

        uint256 expectedRate = (TX_RATE * 3) / 2;
        uint256 expectedFee = TX_SIZE * expectedRate;

        assertEq(networkFee, expectedFee);
        assertEq(transactionRate, expectedRate);
        assertEq(transactionSize, TX_SIZE);
    }

    function test_getNetworkFeeInfo_overload_returnsThreeFields() public {
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        (uint256 transactionRate, uint256 transactionSize, uint256 transactionSizeWithCall) =
            gasService.getNetworkFeeInfo(ETH_CHAIN_ID);

        uint256 expectedRate = (TX_RATE * 3) / 2;

        assertEq(transactionRate, expectedRate);
        assertEq(transactionSize, TX_SIZE);
        assertEq(transactionSizeWithCall, TX_SIZE_WITH_CALL);
    }

    function test_getNetworkFeeInfo_withCallTrue_usesLargerSize() public {
        vm.prank(address(relay));
        gasService.postNetworkFee(ETH_CHAIN_ID, HEIGHT, TX_SIZE, TX_SIZE_WITH_CALL, TX_RATE);

        (uint256 networkFee, , uint256 transactionSize) = gasService.getNetworkFeeInfo(ETH_CHAIN_ID, true);

        // transactionSize should be TX_SIZE_WITH_CALL when withCall=true
        assertEq(transactionSize, TX_SIZE_WITH_CALL);
        assertEq(networkFee, TX_SIZE_WITH_CALL * ((TX_RATE * 3) / 2));
    }
}
