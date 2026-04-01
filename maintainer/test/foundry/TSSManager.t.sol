// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";
import {TSSManager} from "../../contracts/TSSManager.sol";
import {ITSSManager} from "../../contracts/interfaces/ITSSManager.sol";
import {IRelay} from "../../contracts/interfaces/IRelay.sol";
import {TxInItem, TxOutItem, BridgeItem, TxType} from "../../contracts/libs/Types.sol";

// TestTSSManager wrapper removed — _checkSig is not virtual in TSSManager.
// Instead we use vm.mockCall on the ecrecover precompile (address(1)) to return the expected signer.
// See _mockEcrecover() helper below for details.

/// @dev Unit tests for TSSManager.sol — elect, voteUpdateTssPool, voteTxIn/TxOut, voteNetworkFee,
///      slash points, epoch rotation (rotate/retire), and access control.
///
///      _checkSig workaround: TSSManager._checkSig is not virtual so we cannot override it.
///      Instead, we mock the ecrecover precompile at address(1) via vm.mockCall to return the
///      expected signer (address(uint160(uint256(keccak256(pubkey))))).
///      ECDSA.recover internally calls the ecrecover precompile, so the mock intercepts it.
contract TSSManagerTest is BaseTest {
    // The mock relay calls
    address internal mockRelayAddr;

    function setUp() public override {
        // Run parent setUp (deploys TSSManager, wires contracts, mocks precompiles)
        super.setUp();

        mockRelayAddr = mockRelay;

        // Set maintainer limit and register/activate 3 maintainers
        _setMaintainerLimit(10);
        _registerAndActivateMaintainer(validator1, secp256Pubkey1, ed25519Pubkey1, maintainer1);
        _registerAndActivateMaintainer(validator2, secp256Pubkey2, ed25519Pubkey2, maintainer2);
        _registerAndActivateMaintainer(validator3, secp256Pubkey3, ed25519Pubkey3, maintainer3);

        // Mock ecrecover precompile for our test pubkey (used in voteUpdateTssPool _checkSig)
        _mockEcrecoverForPubkey(_make64BytePubkey("tss_pool_key_epoch"));

        // Trigger first election (currentEpoch==0 triggers immediately)
        maintainers.orchestrate();
        // electionEpoch is now 1
    }

    // -------------------------------------------------------------------------
    // Setup/Admin tests
    // -------------------------------------------------------------------------

    /// @dev Admin can call set() to update addresses.
    function test_set_updatesAddresses() public {
        address newMaintainer = makeAddr("newMaintainer");
        address newRelay = makeAddr("newRelay");
        address newParams = makeAddr("newParams");

        vm.prank(admin);
        tssManager.set(newMaintainer, newRelay, newParams);

        assertEq(address(tssManager.maintainerManager()), newMaintainer);
        assertEq(address(tssManager.relay()), newRelay);
        assertEq(address(tssManager.parameters()), newParams);
    }

    /// @dev Unauthorized address cannot call set.
    function test_revert_set_unauthorized() public {
        vm.prank(makeAddr("user1"));
        vm.expectRevert(); // AccessManaged: restricted
        tssManager.set(address(maintainers), mockRelayAddr, address(parameters));
    }

    // -------------------------------------------------------------------------
    // Election tests
    // -------------------------------------------------------------------------

    /// @dev After orchestrate() triggers elect(), the new epoch has KEYGEN_PENDING status.
    function test_elect_setsKeygenPending() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        assertGt(electionEpoch, 0);

        ITSSManager.TSSStatus status = tssManager.getTSSStatus(electionEpoch);
        assertEq(uint256(status), uint256(ITSSManager.TSSStatus.KEYGEN_PENDING));
    }

    /// @dev getEpochPubkey returns empty before keygen is completed.
    function test_getEpochPubkey_returnsEmptyBeforeKeygen() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        bytes memory pubkey = tssManager.getEpochPubkey(electionEpoch);
        assertEq(pubkey.length, 0);
    }

    // -------------------------------------------------------------------------
    // voteUpdateTssPool tests
    // -------------------------------------------------------------------------

    /// @dev Maintainer1 casts a single vote — proposal count increments but consensus not yet reached.
    function test_voteUpdateTssPool_singleVote() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(electionEpoch, false);

        // All 3 elected maintainers must be in members list — vote from maintainer1 only
        // (consensus requires 2 of 3 maintainers with maintainerCount%3==0 -> count >= 2)
        vm.prank(maintainer1);
        tssManager.voteUpdateTssPool(param);

        // Status still KEYGEN_PENDING (1 vote, need 2 for consensus with 3 maintainers)
        assertEq(
            uint256(tssManager.getTSSStatus(electionEpoch)),
            uint256(ITSSManager.TSSStatus.KEYGEN_PENDING)
        );
    }

    /// @dev All 3 maintainers vote same param — consensus reached, status becomes KEYGEN_CONSENSUS,
    ///      then all vote causes KEYGEN_COMPLETED.
    function test_voteUpdateTssPool_reachesConsensus() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(electionEpoch, false);

        // Vote from maintainer1
        vm.prank(maintainer1);
        tssManager.voteUpdateTssPool(param);

        // After 2nd vote consensus reached (3 maintainers, need count >= (3*2)/3 = 2)
        vm.prank(maintainer2);
        tssManager.voteUpdateTssPool(param);

        // After 2 votes: KEYGEN_CONSENSUS
        assertEq(
            uint256(tssManager.getTSSStatus(electionEpoch)),
            uint256(ITSSManager.TSSStatus.KEYGEN_CONSENSUS)
        );

        // 3rd vote completes all members submitting (p.count == members.length == 3) -> KEYGEN_COMPLETED
        vm.prank(maintainer3);
        tssManager.voteUpdateTssPool(param);

        assertEq(
            uint256(tssManager.getTSSStatus(electionEpoch)),
            uint256(ITSSManager.TSSStatus.KEYGEN_COMPLETED)
        );
    }

    /// @dev Non-maintainer cannot vote in voteUpdateTssPool.
    function test_revert_voteUpdateTssPool_notMaintainer() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(electionEpoch, false);

        vm.prank(makeAddr("user1"));
        vm.expectRevert(TSSManager.no_access.selector);
        tssManager.voteUpdateTssPool(param);
    }

    /// @dev Voting for non-current epoch reverts with invalid_status.
    function test_revert_voteUpdateTssPool_wrongEpoch() public {
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(999, false); // wrong epoch

        vm.prank(maintainer1);
        vm.expectRevert(TSSManager.invalid_status.selector);
        tssManager.voteUpdateTssPool(param);
    }

    // -------------------------------------------------------------------------
    // getKeyShare / getMembers tests
    // -------------------------------------------------------------------------

    /// @dev After voteUpdateTssPool, key share is stored for the voting maintainer.
    function test_getKeyShare_returnsStoredShare() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(electionEpoch, false);

        vm.prank(maintainer1);
        tssManager.voteUpdateTssPool(param);

        ITSSManager.KeyShare memory share = tssManager.getKeyShare(maintainer1);
        assertGt(share.keyShare.length, 0);
        assertEq(keccak256(share.pubkey), keccak256(param.pubkey));
    }

    /// @dev After consensus, getMembers returns the elected maintainers for the pubkey.
    function test_getMembers_returnsMemberList() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(electionEpoch, false);

        // Reach consensus with 2 votes
        vm.prank(maintainer1);
        tssManager.voteUpdateTssPool(param);
        vm.prank(maintainer2);
        tssManager.voteUpdateTssPool(param);
        vm.prank(maintainer3);
        tssManager.voteUpdateTssPool(param);

        // After KEYGEN_COMPLETED, getMembers for the pubkey should return elected maintainers
        address[] memory members = tssManager.getMembers(param.pubkey);
        assertEq(members.length, 3);
    }

    // -------------------------------------------------------------------------
    // voteTxIn tests
    // -------------------------------------------------------------------------

    /// @dev Maintainer1 votes on a TxInItem — vote recorded but not yet at consensus.
    function test_voteTxIn_singleVoteRecorded() public {
        // Advance to ACTIVE state first
        _advanceToActiveState();

        TxInItem memory txInItem = _buildTxInItem();

        // Mock relay.executeTxIn to prevent revert
        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.executeTxIn.selector), abi.encode()
        );

        TxInItem[] memory items = new TxInItem[](1);
        items[0] = txInItem;

        // Single vote from maintainer1 (1 of 3, need >= 2 for consensus)
        vm.prank(maintainer1);
        tssManager.voteTxIn(items);
        // If no revert, vote was recorded successfully
    }

    /// @dev After >= 2/3 maintainers vote on same TxInItem, relay.executeTxIn is called.
    function test_voteTxIn_consensusCallsRelay() public {
        _advanceToActiveState();

        TxInItem memory txInItem = _buildTxInItem();
        TxInItem[] memory items = new TxInItem[](1);
        items[0] = txInItem;

        // Mock relay.executeTxIn
        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.executeTxIn.selector), abi.encode()
        );

        vm.prank(maintainer1);
        tssManager.voteTxIn(items);

        vm.expectCall(mockRelayAddr, abi.encodeWithSelector(IRelay.executeTxIn.selector));
        vm.prank(maintainer2);
        tssManager.voteTxIn(items);
    }

    /// @dev Non-maintainer cannot vote txIn — reverts with no_access.
    function test_revert_voteTxIn_notActiveMaintainer() public {
        _advanceToActiveState();

        TxInItem memory txInItem = _buildTxInItem();
        TxInItem[] memory items = new TxInItem[](1);
        items[0] = txInItem;

        vm.prank(makeAddr("user1"));
        vm.expectRevert(TSSManager.no_access.selector);
        tssManager.voteTxIn(items);
    }

    // -------------------------------------------------------------------------
    // voteTxOut tests
    // -------------------------------------------------------------------------

    /// @dev Maintainer votes on TxOutItem — vote recorded.
    function test_voteTxOut_singleVoteRecorded() public {
        _advanceToActiveState();

        TxOutItem memory txOutItem = _buildTxOutItem();
        TxOutItem[] memory items = new TxOutItem[](1);
        items[0] = txOutItem;

        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.executeTxOut.selector), abi.encode()
        );

        vm.prank(maintainer1);
        tssManager.voteTxOut(items);
        // No revert = vote recorded
    }

    /// @dev After consensus, relay.executeTxOut is called.
    function test_voteTxOut_consensusCallsRelay() public {
        _advanceToActiveState();

        TxOutItem memory txOutItem = _buildTxOutItem();
        TxOutItem[] memory items = new TxOutItem[](1);
        items[0] = txOutItem;

        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.executeTxOut.selector), abi.encode()
        );

        vm.prank(maintainer1);
        tssManager.voteTxOut(items);

        vm.expectCall(mockRelayAddr, abi.encodeWithSelector(IRelay.executeTxOut.selector));
        vm.prank(maintainer2);
        tssManager.voteTxOut(items);
    }

    /// @dev Non-maintainer cannot vote txOut.
    function test_revert_voteTxOut_notActiveMaintainer() public {
        _advanceToActiveState();

        TxOutItem memory txOutItem = _buildTxOutItem();
        TxOutItem[] memory items = new TxOutItem[](1);
        items[0] = txOutItem;

        vm.prank(makeAddr("user1"));
        vm.expectRevert(TSSManager.no_access.selector);
        tssManager.voteTxOut(items);
    }

    // -------------------------------------------------------------------------
    // voteNetworkFee tests
    // -------------------------------------------------------------------------

    /// @dev After consensus, relay.postNetworkFee is called.
    function test_voteNetworkFee_consensusPostsFee() public {
        _advanceToActiveState();

        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.postNetworkFee.selector), abi.encode()
        );

        uint256 chain = 1;
        uint256 height = 100;
        uint256 txRate = 50;
        uint256 txSize = 200;
        uint256 txSizeWithCall = 300;

        vm.prank(maintainer1);
        tssManager.voteNetworkFee(chain, height, txRate, txSize, txSizeWithCall);

        vm.expectCall(mockRelayAddr, abi.encodeWithSelector(IRelay.postNetworkFee.selector));
        vm.prank(maintainer2);
        tssManager.voteNetworkFee(chain, height, txRate, txSize, txSizeWithCall);
    }

    // -------------------------------------------------------------------------
    // Slash point tests
    // -------------------------------------------------------------------------

    /// @dev getSlashPoint returns 0 initially for a new maintainer.
    function test_getSlashPoint_returnsZeroInitially() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        uint256 point = tssManager.getSlashPoint(electionEpoch, maintainer1);
        assertEq(point, 0);
    }

    /// @dev batchGetSlashPoint returns correct array for multiple maintainers.
    function test_batchGetSlashPoint_returnsMultiple() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        address[] memory ms = new address[](3);
        ms[0] = maintainer1;
        ms[1] = maintainer2;
        ms[2] = maintainer3;

        uint256[] memory points = tssManager.batchGetSlashPoint(electionEpoch, ms);
        assertEq(points.length, 3);
        assertEq(points[0], 0);
        assertEq(points[1], 0);
        assertEq(points[2], 0);
    }

    // -------------------------------------------------------------------------
    // Rotate / Retire tests
    // -------------------------------------------------------------------------

    /// @dev rotate() updates epoch status to MIGRATING/RETIRING (called by maintainers contract).
    function test_rotate_updatesEpochStatus() public {
        uint256 electionEpoch = maintainers.electionEpoch();

        // Complete voteUpdateTssPool to get to KEYGEN_COMPLETED
        _reachKeygenCompleted(electionEpoch);

        // Now orchestrate should call rotate
        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.rotate.selector), abi.encode()
        );

        maintainers.orchestrate();

        // After rotate, the electionEpoch should become MIGRATING
        // (tssManager.currentEpoch was updated to electionEpoch)
        assertEq(
            uint256(tssManager.getTSSStatus(electionEpoch)),
            uint256(ITSSManager.TSSStatus.MIGRATING)
        );
    }

    /// @dev Cannot call rotate from non-maintainer address.
    function test_revert_rotate_notMaintainer() public {
        vm.prank(makeAddr("user1"));
        vm.expectRevert(TSSManager.no_access.selector);
        tssManager.rotate(0, 1);
    }

    /// @dev retire() marks old epoch RETIRED and new epoch ACTIVE.
    function test_retire_marksEpochMigrated() public {
        uint256 electionEpoch = maintainers.electionEpoch();
        _reachKeygenCompleted(electionEpoch);

        vm.mockCall(mockRelayAddr, abi.encodeWithSelector(IRelay.rotate.selector), abi.encode());
        maintainers.orchestrate(); // triggers rotate

        // Mock migrate to return true (migration complete)
        vm.mockCall(
            mockRelayAddr,
            abi.encodeWithSelector(IRelay.migrate.selector),
            abi.encode(true)
        );
        vm.prank(address(maintainers));
        tssManager.migrate();

        // Status should be MIGRATED now
        assertEq(
            uint256(tssManager.getTSSStatus(electionEpoch)),
            uint256(ITSSManager.TSSStatus.MIGRATED)
        );

        // Now orchestrate again to trigger retire
        maintainers.orchestrate();

        // After retire: electionEpoch becomes ACTIVE, currentEpoch is updated
        assertEq(
            uint256(tssManager.getTSSStatus(electionEpoch)),
            uint256(ITSSManager.TSSStatus.ACTIVE)
        );
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Mock the ecrecover precompile (address 0x01) so that _checkSig passes for our test pubkey.
    ///      _checkSig requires: ECDSA.recover(keccak256(pubkey), signature) == address(uint160(uint256(keccak256(pubkey))))
    ///      We mock ALL calls to address(1) to return the expected signer derived from our pubkey.
    ///      This intercepts ECDSA.recover's internal ecrecover call.
    function _mockEcrecoverForPubkey(bytes memory pubkey) internal {
        bytes32 pubkeyHash = keccak256(pubkey);
        address expectedSigner = address(uint160(uint256(pubkeyHash)));
        // ecrecover returns a 32-byte padded address; match any calldata (empty bytes = wildcard)
        vm.mockCall(address(1), new bytes(0), abi.encode(expectedSigner));
    }

    /// @dev Build a TssPoolParam with the 3 elected maintainers for a given epoch.
    function _buildTssPoolParam(uint256 epoch, bool isFailure)
        internal
        view
        returns (TSSManager.TssPoolParam memory param)
    {
        bytes memory pubkey = _make64BytePubkey("tss_pool_key_epoch");
        bytes memory keyShare = abi.encodePacked(keccak256("keyshare"));
        bytes memory sig = abi.encodePacked(bytes32(0), bytes32(0), uint8(28)); // dummy sig, ecrecover mocked

        address[] memory members = new address[](3);
        members[0] = maintainer1;
        members[1] = maintainer2;
        members[2] = maintainer3;

        address[] memory blames = new address[](0);
        if (isFailure) {
            // Non-empty blames indicates key gen failure
            blames = new address[](1);
            blames[0] = maintainer3;
        }

        param = TSSManager.TssPoolParam({
            epoch: epoch,
            pubkey: pubkey,
            keyShare: keyShare,
            members: members,
            blames: blames,
            signature: sig
        });
    }

    /// @dev Advances the system to ACTIVE state:
    ///      1. voteUpdateTssPool with all 3 maintainers -> KEYGEN_COMPLETED
    ///      2. orchestrate() -> rotate (mocked) -> MIGRATING
    ///      3. migrate() -> MIGRATED
    ///      4. orchestrate() -> retire -> ACTIVE
    function _advanceToActiveState() internal {
        uint256 electionEpoch = maintainers.electionEpoch();
        _reachKeygenCompleted(electionEpoch);

        vm.mockCall(mockRelayAddr, abi.encodeWithSelector(IRelay.rotate.selector), abi.encode());
        maintainers.orchestrate(); // triggers rotate

        vm.mockCall(
            mockRelayAddr, abi.encodeWithSelector(IRelay.migrate.selector), abi.encode(true)
        );
        vm.prank(address(maintainers));
        tssManager.migrate(); // MIGRATED

        maintainers.orchestrate(); // retire -> ACTIVE
    }

    /// @dev Complete voteUpdateTssPool for all 3 maintainers, reaching KEYGEN_COMPLETED.
    function _reachKeygenCompleted(uint256 electionEpoch) internal {
        TSSManager.TssPoolParam memory param = _buildTssPoolParam(electionEpoch, false);
        vm.prank(maintainer1);
        tssManager.voteUpdateTssPool(param);
        vm.prank(maintainer2);
        tssManager.voteUpdateTssPool(param);
        vm.prank(maintainer3);
        tssManager.voteUpdateTssPool(param);
    }

    /// @dev Build a simple TxInItem for testing.
    function _buildTxInItem() internal view returns (TxInItem memory) {
        // The vault bytes must hash to the active pubkey used in setUp
        bytes memory vaultBytes = _make64BytePubkey("tss_pool_key_epoch");

        BridgeItem memory bridgeItem = BridgeItem({
            chainAndGasLimit: uint256(1) << 192, // fromChain = 1
            vault: vaultBytes,
            txType: TxType.TRANSFER,
            sequence: 1,
            token: abi.encodePacked(address(0)),
            amount: 1 ether,
            from: abi.encodePacked(address(0x1234)),
            to: abi.encodePacked(address(0x5678)),
            payload: ""
        });

        return TxInItem({
            orderId: keccak256("order1"),
            bridgeItem: bridgeItem,
            height: 100,
            refundAddr: abi.encodePacked(address(0x1234))
        });
    }

    /// @dev Build a simple TxOutItem for testing.
    function _buildTxOutItem() internal view returns (TxOutItem memory) {
        bytes memory vaultBytes = _make64BytePubkey("tss_pool_key_epoch");

        BridgeItem memory bridgeItem = BridgeItem({
            chainAndGasLimit: uint256(1) << 192,
            vault: vaultBytes,
            txType: TxType.TRANSFER,
            sequence: 1,
            token: abi.encodePacked(address(0)),
            amount: 1 ether,
            from: abi.encodePacked(address(0x1234)),
            to: abi.encodePacked(address(0x5678)),
            payload: ""
        });

        return TxOutItem({
            orderId: keccak256("order2"),
            bridgeItem: bridgeItem,
            height: 100,
            gasUsed: 50000,
            sender: address(0x1234)
        });
    }
}
