// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {AuthorityManager} from "@mapprotocol/common-contracts/contracts/AuthorityManager.sol";

import {Registry} from "../../contracts/Registry.sol";
import {GasService} from "../../contracts/GasService.sol";
import {VaultManager} from "../../contracts/VaultManager.sol";
import {Relay} from "../../contracts/Relay.sol";
import {ProtocolFee} from "../../contracts/ProtocolFee.sol";
import {ERC1967Proxy} from "../../contracts/ERC1967Proxy.sol";

import {ContractType, ChainType} from "../../contracts/libs/Types.sol";

import {MockToken} from "./MockToken.sol";

/// @dev Shared test fixture that deploys the full protocol suite behind UUPS proxies.
/// All test contracts inherit this to get a pre-wired environment.
contract BaseTest is Test {
    // -----------------------------------------------------------------------
    // Deployed contracts
    // -----------------------------------------------------------------------

    AuthorityManager public authority;
    Registry public registry;
    GasService public gasService;
    VaultManager public vaultManager;
    Relay public relay;
    ProtocolFee public protocolFee;

    MockToken public testToken;
    MockToken public testToken6;

    // -----------------------------------------------------------------------
    // Test accounts
    // -----------------------------------------------------------------------

    address public admin = address(0xA11CE);
    address public user1 = address(0xB0B);
    address public user2 = address(0xCA1);

    // TSS key material — tssAddress is vm.addr(tssPrivateKey), used for signing.
    // tssPubkey is deterministic 64-byte vault bytes passed to setTssAddress / rotate.
    uint256 public tssPrivateKey;
    address public tssAddress;
    bytes public tssPubkey;

    // Used when registering ContractType.TSS_MANAGER in the Registry
    address public mockTssManager;

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    uint256 public constant SELF_CHAIN_ID = 22776; // MAPO relay chain
    uint256 public constant ETH_CHAIN_ID = 1;
    uint256 public constant BSC_CHAIN_ID = 56;

    // -----------------------------------------------------------------------
    // setUp
    // -----------------------------------------------------------------------

    function setUp() public virtual {
        // Set chain ID to MAPO relay chain so immutable selfChainId == SELF_CHAIN_ID
        vm.chainId(SELF_CHAIN_ID);

        // Derive TSS key material
        tssPrivateKey = uint256(keccak256("tss_test_key"));
        tssAddress = vm.addr(tssPrivateKey);
        tssPubkey = _makeVaultBytes("tss");

        mockTssManager = makeAddr("tssManager");

        // 1. Deploy AuthorityManager — admin is the default AccessManager admin
        vm.prank(admin);
        authority = new AuthorityManager(admin);

        // 2. Deploy MockToken instances first (needed for chain registration)
        testToken = new MockToken("Test Token", "TT", 18);
        testToken6 = new MockToken("Test USDC", "TUSDC", 6);

        // 3. Deploy Registry behind UUPS proxy
        address registryProxy = _deployProxy(
            address(new Registry()),
            abi.encodeCall(Registry.initialize, (address(authority)))
        );
        registry = Registry(registryProxy);

        // 4. Deploy GasService behind UUPS proxy
        address gasServiceProxy = _deployProxy(
            address(new GasService()),
            abi.encodeCall(GasService.initialize, (address(authority)))
        );
        gasService = GasService(gasServiceProxy);

        // 5. Deploy VaultManager behind UUPS proxy
        address vaultManagerProxy = _deployProxy(
            address(new VaultManager()),
            abi.encodeCall(VaultManager.initialize, (address(authority)))
        );
        vaultManager = VaultManager(vaultManagerProxy);

        // 6. Deploy ProtocolFee behind UUPS proxy
        address protocolFeeProxy = _deployProxy(
            address(new ProtocolFee()),
            abi.encodeCall(ProtocolFee.initialize, (address(authority)))
        );
        protocolFee = ProtocolFee(payable(protocolFeeProxy));

        // 7. Deploy Relay behind UUPS proxy
        address relayProxy = _deployProxy(
            address(new Relay()),
            abi.encodeCall(Relay.initialize, (address(authority)))
        );
        relay = Relay(payable(relayProxy));

        // 8. Wire contracts together (all setters are restricted — prank as admin)
        vm.startPrank(admin);

        // GasService needs registry to resolve ContractType.RELAY for access control
        gasService.setRegistry(address(registry));

        // VaultManager needs relay and registry
        vaultManager.setRegistry(address(registry));
        vaultManager.setRelay(address(relay));

        // Relay needs vaultManager and registry
        relay.setVaultManager(address(vaultManager));
        relay.setRegistry(address(registry));

        // Register all contracts in the Registry
        registry.registerContract(ContractType.RELAY, address(relay));
        registry.registerContract(ContractType.GAS_SERVICE, address(gasService));
        registry.registerContract(ContractType.VAULT_MANAGER, address(vaultManager));
        registry.registerContract(ContractType.PROTOCOL_FEE, address(protocolFee));
        registry.registerContract(ContractType.TSS_MANAGER, mockTssManager);

        // 9. Register SELF_CHAIN_ID (MAPO relay chain)
        // Use real token addresses (not address(0)) to avoid amount conversion issues
        registry.registerChain(
            SELF_CHAIN_ID,
            ChainType.CONTRACT,
            bytes(""),
            address(testToken),
            address(testToken),
            "MAPO"
        );

        // 10. Register ETH_CHAIN_ID
        registry.registerChain(
            ETH_CHAIN_ID,
            ChainType.CONTRACT,
            bytes(""),
            address(testToken),
            address(testToken),
            "Ethereum"
        );

        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// @dev Deploy an implementation behind an ERC1967 proxy with initialization calldata.
    function _deployProxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    /// @dev Register a relay-chain token + map a source-chain token to it.
    ///      Calls registerToken then mapToken with admin prank.
    function _registerToken(address token, uint96 tokenId, uint256 fromChain, bytes memory chainToken, uint8 decimals)
        internal
    {
        vm.startPrank(admin);
        registry.registerToken(tokenId, token);
        registry.mapToken(token, fromChain, chainToken, decimals);
        vm.stopPrank();
    }

    /// @dev Generate deterministic 64-byte "public key" bytes for vault/TSS operations.
    ///      These bytes are hashed by Utils.getAddressFromPublicKey to produce an address.
    function _makeVaultBytes(string memory label) internal pure returns (bytes memory) {
        return abi.encodePacked(
            keccak256(abi.encodePacked(label, "_x")),
            keccak256(abi.encodePacked(label, "_y"))
        );
    }

    /// @dev Compute the address that Utils.getAddressFromPublicKey would return for given pubkey bytes.
    ///      Equivalent to: address(uint160(uint256(keccak256(pubkey))))
    function _pubkeyToAddress(bytes memory pubkey) internal pure returns (address) {
        return address(uint160(uint256(keccak256(pubkey))));
    }
}
