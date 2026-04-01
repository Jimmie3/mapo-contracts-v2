// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {Maintainers} from "../../contracts/Maintainers.sol";
import {TSSManager} from "../../contracts/TSSManager.sol";
import {Parameters} from "../../contracts/Parameters.sol";
import {ERC1967Proxy} from "../../contracts/ERC1967Proxy.sol";
import {AuthorityManager} from "@mapprotocol/common-contracts/contracts/AuthorityManager.sol";

import {IElection} from "../../contracts/interfaces/IElection.sol";
import {IAccounts} from "../../contracts/interfaces/IAccounts.sol";
import {IValidators} from "../../contracts/interfaces/IValidators.sol";
import {IMaintainers} from "../../contracts/interfaces/IMaintainers.sol";

/// @dev Shared test base for maintainer module unit tests.
///      Deploys Maintainers, TSSManager, Parameters, and AuthorityManager behind proxies.
///      Mocks MAP chain precompiles (IElection, IAccounts, IValidators) via vm.mockCall.
contract BaseTest is Test {
    // ----- Precompile addresses -----
    address internal constant ACCOUNTS_ADDRESS = 0x000000000000000000000000000000000000d010;
    address internal constant VALIDATORS_ADDRESS = 0x000000000000000000000000000000000000D012;
    address internal constant ELECTIONS_ADDRESS = 0x000000000000000000000000000000000000d013;

    // ----- Deployed contracts -----
    AuthorityManager public authority;
    Maintainers public maintainers;
    TSSManager public tssManager;
    Parameters public parameters;

    // ----- Test actors -----
    address public admin = address(0xA11CE);

    // Validators (register maintainers)
    address public validator1;
    uint256 public validator1Key;
    address public validator2;
    uint256 public validator2Key;
    address public validator3;
    uint256 public validator3Key;

    // Maintainer accounts (activate/revoke)
    // NOTE: maintainerN address is derived as address(uint160(uint256(keccak256(secp256PubkeyN))))
    //       so we fix the pubkey bytes first and derive addresses from them.
    bytes public secp256Pubkey1;
    bytes public secp256Pubkey2;
    bytes public secp256Pubkey3;
    bytes public secp256Pubkey4;
    bytes public ed25519Pubkey1;
    bytes public ed25519Pubkey2;
    bytes public ed25519Pubkey3;
    bytes public ed25519Pubkey4;

    address public maintainer1;
    address public maintainer2;
    address public maintainer3;
    address public maintainer4;

    address public mockRelay;

    // ----- Parameter key hashes (matching Maintainers.sol private constants) -----
    bytes32 internal constant REWARD_PER_BLOCK = keccak256(bytes("REWARD_PER_BLOCK"));
    bytes32 internal constant BLOCKS_PER_EPOCH = keccak256(bytes("BLOCKS_PER_EPOCH"));
    bytes32 internal constant MAX_BLOCKS_FOR_UPDATE_TSS = keccak256("MAX_BLOCKS_FOR_UPDATE_TSS");
    bytes32 internal constant MAX_SLASH_POINT_FOR_ELECT = keccak256(bytes("MAX_SLASH_POINT_FOR_ELECT"));
    bytes32 internal constant JAIL_BLOCK = keccak256(bytes("JAIL_BLOCK"));
    bytes32 internal constant ADDITIONAL_REWARD_MAX_SLASH_POINT =
        keccak256(bytes("ADDITIONAL_REWARD_MAX_SLASH_POINT"));

    function setUp() public virtual {
        // Create validator keypairs
        (validator1, validator1Key) = makeAddrAndKey("validator1");
        (validator2, validator2Key) = makeAddrAndKey("validator2");
        (validator3, validator3Key) = makeAddrAndKey("validator3");

        mockRelay = makeAddr("relay");

        // Build 64-byte secp256 pubkeys and derive maintainer addresses from them.
        // The Maintainers contract checks: address(uint160(uint256(keccak256(pubkey)))) == maintainerAddr
        // So we fix known pubkey bytes and derive the address.
        secp256Pubkey1 = _make64BytePubkey("maintainer1_secp256");
        secp256Pubkey2 = _make64BytePubkey("maintainer2_secp256");
        secp256Pubkey3 = _make64BytePubkey("maintainer3_secp256");
        secp256Pubkey4 = _make64BytePubkey("maintainer4_secp256");

        ed25519Pubkey1 = abi.encodePacked(keccak256("maintainer1_ed25519")); // 32 bytes
        ed25519Pubkey2 = abi.encodePacked(keccak256("maintainer2_ed25519"));
        ed25519Pubkey3 = abi.encodePacked(keccak256("maintainer3_ed25519"));
        ed25519Pubkey4 = abi.encodePacked(keccak256("maintainer4_ed25519"));

        // Derive maintainer addresses from pubkeys (matching contract logic)
        maintainer1 = _pubkeyToAddress(secp256Pubkey1);
        maintainer2 = _pubkeyToAddress(secp256Pubkey2);
        maintainer3 = _pubkeyToAddress(secp256Pubkey3);
        maintainer4 = _pubkeyToAddress(secp256Pubkey4);

        // Deploy AuthorityManager
        authority = new AuthorityManager(admin);

        // Deploy Parameters behind proxy
        Parameters parametersImpl = new Parameters();
        bytes memory parametersInit = abi.encodeWithSelector(Parameters.initialize.selector, address(authority));
        parameters = Parameters(address(new ERC1967Proxy(address(parametersImpl), parametersInit)));

        // Deploy Maintainers behind proxy
        Maintainers maintainersImpl = new Maintainers();
        bytes memory maintainersInit =
            abi.encodeWithSelector(Maintainers.initialize.selector, address(authority));
        maintainers = Maintainers(payable(address(new ERC1967Proxy(address(maintainersImpl), maintainersInit))));

        // Deploy TSSManager behind proxy
        TSSManager tssManagerImpl = new TSSManager();
        bytes memory tssManagerInit =
            abi.encodeWithSelector(TSSManager.initialize.selector, address(authority));
        tssManager = TSSManager(address(new ERC1967Proxy(address(tssManagerImpl), tssManagerInit)));

        // Wire contracts (admin calling restricted functions)
        vm.startPrank(admin);
        tssManager.set(address(maintainers), mockRelay, address(parameters));
        maintainers.set(address(tssManager), address(parameters));
        vm.stopPrank();

        // Set system parameters via admin
        _setParameters();

        // Mock MAP chain precompiles
        _setupPrecompileMocks();
    }

    // ----- Internal helpers -----

    /// @dev Sets required parameters via the admin using the Parameters contract's set() function.
    function _setParameters() internal {
        vm.startPrank(admin);
        parameters.set("BLOCKS_PER_EPOCH", 100);
        parameters.set("MAX_BLOCKS_FOR_UPDATE_TSS", 500);
        parameters.set("MAX_SLASH_POINT_FOR_ELECT", 100);
        parameters.set("JAIL_BLOCK", 200);
        parameters.set("REWARD_PER_BLOCK", 1 ether);
        parameters.set("ADDITIONAL_REWARD_MAX_SLASH_POINT", 50);
        parameters.set("OBSERVE_SLASH_POINT", 1);
        parameters.set("OBSERVE_DELAY_SLASH_POINT", 5);
        parameters.set("KEY_GEN_DELAY_SLASH_POINT", 200);
        parameters.set("KEY_GEN_FAIL_SLASH_POINT", 10);
        parameters.set("MIGRATION_DELAY_SLASH_POINT", 10);
        parameters.set("OBSERVE_MAX_DELAY_BLOCK", 50);
        vm.stopPrank();
    }

    /// @dev Also set maintainerLimit so election can proceed
    function _setMaintainerLimit(uint256 limit) internal {
        vm.prank(admin);
        maintainers.updateMaintainerLimit(limit);
    }

    /// @dev Mock all three MAP chain precompiles used by Maintainers.sol.
    ///      Uses vm.mockCall which applies for all subsequent calls during a test.
    function _setupPrecompileMocks() internal {
        // --- IElection at 0xd013 ---
        // getCurrentValidatorSigners() returns address[] — used by _getCurrentValidators()
        address[] memory validatorSigners = new address[](3);
        validatorSigners[0] = validator1;
        validatorSigners[1] = validator2;
        validatorSigners[2] = validator3;
        vm.mockCall(
            ELECTIONS_ADDRESS,
            abi.encodeWithSelector(IElection.getCurrentValidatorSigners.selector),
            abi.encode(validatorSigners)
        );

        // --- IAccounts at 0xd010 ---
        // validatorSignerToAccount(address) returns address — used by _getCurrentValidators() and _isValidator()
        // Simplification: signer == account in tests
        vm.mockCall(
            ACCOUNTS_ADDRESS,
            abi.encodeWithSelector(IAccounts.validatorSignerToAccount.selector, validator1),
            abi.encode(validator1)
        );
        vm.mockCall(
            ACCOUNTS_ADDRESS,
            abi.encodeWithSelector(IAccounts.validatorSignerToAccount.selector, validator2),
            abi.encode(validator2)
        );
        vm.mockCall(
            ACCOUNTS_ADDRESS,
            abi.encodeWithSelector(IAccounts.validatorSignerToAccount.selector, validator3),
            abi.encode(validator3)
        );

        // --- IValidators at 0xD012 ---
        // isValidator(address) returns bool — used by _isValidator()
        vm.mockCall(
            VALIDATORS_ADDRESS,
            abi.encodeWithSelector(IValidators.isValidator.selector, validator1),
            abi.encode(true)
        );
        vm.mockCall(
            VALIDATORS_ADDRESS,
            abi.encodeWithSelector(IValidators.isValidator.selector, validator2),
            abi.encode(true)
        );
        vm.mockCall(
            VALIDATORS_ADDRESS,
            abi.encodeWithSelector(IValidators.isValidator.selector, validator3),
            abi.encode(true)
        );
    }

    /// @dev Register a maintainer (validator calls) and activate it (maintainer calls).
    function _registerAndActivateMaintainer(
        address validator,
        bytes memory secp256Pubkey,
        bytes memory ed25519Pubkey,
        address maintainerAddr
    ) internal {
        string memory p2pAddr = "/ip4/127.0.0.1/tcp/30303";
        vm.prank(validator);
        maintainers.register(maintainerAddr, secp256Pubkey, ed25519Pubkey, p2pAddr);

        vm.prank(maintainerAddr);
        maintainers.activate();
    }

    /// @dev Creates a deterministic 64-byte pubkey from a seed string.
    function _make64BytePubkey(string memory seed) internal pure returns (bytes memory) {
        bytes32 part1 = keccak256(abi.encodePacked(seed, "_x"));
        bytes32 part2 = keccak256(abi.encodePacked(seed, "_y"));
        return abi.encodePacked(part1, part2);
    }

    /// @dev Derive maintainer address from secp256 pubkey (matching Maintainers._getAddressFromPublicKey).
    function _pubkeyToAddress(bytes memory pubkey) internal pure returns (address) {
        return address(uint160(uint256(keccak256(pubkey))));
    }
}
