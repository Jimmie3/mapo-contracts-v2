// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";
import {ContractType, ChainType} from "../../contracts/libs/Types.sol";
import {Utils} from "../../contracts/libs/Utils.sol";

contract RegistryTest is BaseTest {
    // -----------------------------------------------------------------------
    // Contract registration
    // -----------------------------------------------------------------------

    function test_registerContract_setsAddress() public {
        address newAddr = makeAddr("newGasService");
        vm.prank(admin);
        registry.registerContract(ContractType.GAS_SERVICE, newAddr);
        assertEq(registry.getContractAddress(ContractType.GAS_SERVICE), newAddr);
    }

    function test_revert_registerContract_zeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.registerContract(ContractType.RELAY, address(0));
    }

    function test_revert_registerContract_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.registerContract(ContractType.RELAY, makeAddr("relay2"));
    }

    // -----------------------------------------------------------------------
    // Chain registration
    // -----------------------------------------------------------------------

    function test_registerChain_addsChain() public {
        vm.prank(admin);
        registry.registerChain(
            BSC_CHAIN_ID,
            ChainType.CONTRACT,
            bytes(""),
            address(testToken),
            address(testToken),
            "BSC"
        );
        assertTrue(registry.isRegistered(BSC_CHAIN_ID));
        assertEq(uint256(registry.getChainType(BSC_CHAIN_ID)), uint256(ChainType.CONTRACT));

        // BSC_CHAIN_ID should appear in the chains list
        uint256[] memory chains = registry.getChains();
        bool found = false;
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] == BSC_CHAIN_ID) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_registerChain_withRouter() public {
        bytes memory router = bytes("0x1234567890abcdef");
        vm.prank(admin);
        registry.registerChain(
            BSC_CHAIN_ID,
            ChainType.CONTRACT,
            router,
            address(testToken),
            address(testToken),
            "BSC"
        );
        assertEq(registry.getChainRouters(BSC_CHAIN_ID), router);
    }

    function test_deregisterChain_removesChain() public {
        // Register a new chain with no tokens
        vm.prank(admin);
        registry.registerChain(
            BSC_CHAIN_ID,
            ChainType.CONTRACT,
            bytes(""),
            address(testToken),
            address(testToken),
            "BSC"
        );
        assertTrue(registry.isRegistered(BSC_CHAIN_ID));

        // Deregister — no tokens mapped, should succeed
        vm.prank(admin);
        registry.deregisterChain(BSC_CHAIN_ID);
        assertFalse(registry.isRegistered(BSC_CHAIN_ID));
    }

    function test_revert_deregisterChain_hasTokens() public {
        // Register BSC
        vm.prank(admin);
        registry.registerChain(
            BSC_CHAIN_ID,
            ChainType.CONTRACT,
            bytes(""),
            address(testToken),
            address(testToken),
            "BSC"
        );

        // Register relay token and map it to BSC
        vm.startPrank(admin);
        registry.registerToken(1, address(testToken));
        bytes memory bscToken = abi.encodePacked(address(testToken));
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken, 18);
        vm.stopPrank();

        // Now deregister should fail because there are mapped tokens
        vm.prank(admin);
        vm.expectRevert();
        registry.deregisterChain(BSC_CHAIN_ID);
    }

    function test_revert_registerChain_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.registerChain(BSC_CHAIN_ID, ChainType.CONTRACT, bytes(""), address(testToken), address(testToken), "BSC");
    }

    // -----------------------------------------------------------------------
    // Token registration and mapping
    // -----------------------------------------------------------------------

    function test_registerToken_setsTokenId() public {
        vm.prank(admin);
        registry.registerToken(42, address(testToken));
        assertEq(registry.getTokenAddressById(42), address(testToken));
    }

    function test_mapToken_createsMapping() public {
        // Register BSC first
        vm.prank(admin);
        registry.registerChain(
            BSC_CHAIN_ID,
            ChainType.CONTRACT,
            bytes(""),
            address(testToken),
            address(testToken),
            "BSC"
        );

        // Register relay token
        vm.prank(admin);
        registry.registerToken(1, address(testToken));

        // Map BSC token to relay token
        bytes memory bscToken = abi.encodePacked(address(testToken6));
        vm.prank(admin);
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken, 18);

        // Verify mapping
        address relayToken = registry.getRelayChainToken(BSC_CHAIN_ID, bscToken);
        assertEq(relayToken, address(testToken));
    }

    function test_mapToken_withDecimals() public {
        // Register BSC
        vm.prank(admin);
        registry.registerChain(BSC_CHAIN_ID, ChainType.CONTRACT, bytes(""), address(testToken), address(testToken), "BSC");

        // Register relay token (18 decimals)
        vm.prank(admin);
        registry.registerToken(1, address(testToken));

        // Map BSC token with 6 decimals
        bytes memory bscToken = abi.encodePacked(address(testToken6));
        vm.prank(admin);
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken, 6);

        // 1e18 relay amount -> 1e6 on BSC (18 -> 6 decimals)
        uint256 toChainAmount = registry.getToChainAmount(address(testToken), 1e18, BSC_CHAIN_ID);
        assertEq(toChainAmount, 1e6);
    }

    function test_unmapToken_removesMapping() public {
        // Set up BSC chain + token mapping
        vm.prank(admin);
        registry.registerChain(BSC_CHAIN_ID, ChainType.CONTRACT, bytes(""), address(testToken), address(testToken), "BSC");
        vm.prank(admin);
        registry.registerToken(1, address(testToken));

        bytes memory bscToken = abi.encodePacked(address(testToken6));
        vm.prank(admin);
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken, 18);

        // Verify it's mapped
        assertEq(registry.getRelayChainToken(BSC_CHAIN_ID, bscToken), address(testToken));

        // Unmap
        vm.prank(admin);
        registry.unmapToken(BSC_CHAIN_ID, bscToken);

        // After unmap, mapping returns address(0)
        assertEq(registry.getRelayChainToken(BSC_CHAIN_ID, bscToken), address(0));
    }

    function test_revert_mapToken_unauthorized() public {
        vm.prank(admin);
        registry.registerChain(BSC_CHAIN_ID, ChainType.CONTRACT, bytes(""), address(testToken), address(testToken), "BSC");
        vm.prank(admin);
        registry.registerToken(1, address(testToken));

        bytes memory bscToken = abi.encodePacked(address(testToken6));
        vm.prank(user1);
        vm.expectRevert();
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken, 18);
    }

    // -----------------------------------------------------------------------
    // Alias / ticker tests
    // -----------------------------------------------------------------------

    function test_setTokenTicker_setsNickname() public {
        bytes memory tokenBytes = abi.encodePacked(address(testToken));
        vm.prank(admin);
        registry.setTokenTicker(ETH_CHAIN_ID, tokenBytes, "WETH");

        string memory nickname = registry.getTokenNickname(ETH_CHAIN_ID, tokenBytes);
        assertEq(nickname, "WETH");
    }

    function test_getTokenAddressByNickname_returnsToken() public {
        bytes memory tokenBytes = abi.encodePacked(address(testToken));
        vm.prank(admin);
        registry.setTokenTicker(ETH_CHAIN_ID, tokenBytes, "WETH");

        bytes memory result = registry.getTokenAddressByNickname(ETH_CHAIN_ID, "WETH");
        assertEq(result, tokenBytes);
    }

    function test_getChainName_returnsName() public {
        string memory name = registry.getChainName(ETH_CHAIN_ID);
        assertEq(name, "Ethereum");
    }

    function test_getChainByName_returnsChainId() public {
        uint256 chainId = registry.getChainByName("MAPO");
        assertEq(chainId, SELF_CHAIN_ID);
    }

    // -----------------------------------------------------------------------
    // View functions — tokens and decimals
    // -----------------------------------------------------------------------

    function test_getToChainToken_returnsCorrectToken() public {
        // For relay chain: getToChainToken(token, selfChainId) returns Utils.toBytes(token)
        bytes memory expected = Utils.toBytes(address(testToken));
        bytes memory result = registry.getToChainToken(address(testToken), SELF_CHAIN_ID);
        assertEq(result, expected);
    }

    function test_getTargetAmount_decimalConversion() public {
        // Register BSC with a 6-decimal mapped token
        vm.prank(admin);
        registry.registerChain(BSC_CHAIN_ID, ChainType.CONTRACT, bytes(""), address(testToken), address(testToken), "BSC");
        vm.prank(admin);
        registry.registerToken(1, address(testToken));

        bytes memory bscToken = abi.encodePacked(address(testToken6));
        vm.prank(admin);
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken, 6);

        // Convert 1000e18 relay amount to BSC (6 decimals): expect 1000e6
        uint256 amount = registry.getTargetAmount(SELF_CHAIN_ID, BSC_CHAIN_ID, Utils.toBytes(address(testToken)), 1000e18);
        assertEq(amount, 1000e6);
    }

    function test_getChainTokens_returnsAllTokens() public {
        // Register BSC and map two tokens
        vm.prank(admin);
        registry.registerChain(BSC_CHAIN_ID, ChainType.CONTRACT, bytes(""), address(testToken), address(testToken), "BSC");
        vm.prank(admin);
        registry.registerToken(1, address(testToken));
        vm.prank(admin);
        registry.registerToken(2, address(testToken6));

        bytes memory bscToken1 = abi.encodePacked(address(testToken));
        bytes memory bscToken2 = abi.encodePacked(address(testToken6));

        vm.prank(admin);
        registry.mapToken(address(testToken), BSC_CHAIN_ID, bscToken1, 18);
        vm.prank(admin);
        registry.mapToken(address(testToken6), BSC_CHAIN_ID, bscToken2, 6);

        bytes[] memory tokens = registry.getChainTokens(BSC_CHAIN_ID);
        assertEq(tokens.length, 2);
    }

    function test_getTokenDecimals_returnsDecimals() public {
        // Register relay token — decimals[selfChainId] is set by registerToken via IERC20Metadata
        vm.prank(admin);
        registry.registerToken(1, address(testToken));

        bytes memory tokenBytes = Utils.toBytes(address(testToken));
        uint256 decimals = registry.getTokenDecimals(SELF_CHAIN_ID, tokenBytes);
        assertEq(decimals, 18);
    }

    function test_getChainGasToken_returnsToken() public {
        assertEq(registry.getChainGasToken(ETH_CHAIN_ID), address(testToken));
    }

    function test_getChainBaseToken_returnsToken() public {
        assertEq(registry.getChainBaseToken(ETH_CHAIN_ID), address(testToken));
    }

    function test_revert_setTokenTicker_unauthorized() public {
        bytes memory tokenBytes = abi.encodePacked(address(testToken));
        vm.prank(user1);
        vm.expectRevert();
        registry.setTokenTicker(ETH_CHAIN_ID, tokenBytes, "WETH");
    }
}
