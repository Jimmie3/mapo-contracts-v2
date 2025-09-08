// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Utils} from "./libs/Utils.sol";
import {Constant} from "./libs/Constant.sol";
import {IParameters} from "./interfaces/IParameters.sol";
import {ITSSManager} from "./interfaces/ITSSManager.sol";
import {IRelay} from "./interfaces/IRelay.sol";
import {IMaintainers} from "./interfaces/IMaintainers.sol";
import {TxInItem, TxOutItem, TxType} from "./libs/Types.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract TSSManager is BaseImplementation, ITSSManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    // electing epoch hasn't gen tss key
    bytes32 private constant ELECTING_PUBKEY_HASH = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 private activePubkey;
    bytes32 private retirePubkey;

    uint256 public currentEpoch;

    struct TSSInfo {
        TSSStatus status;
        uint64 electBlock;
        //uint128 startBlock;
        //uint128 endBlock;
        //uint128 migrateBlock;
        uint64 threshold;

        uint256 epochId;
        bytes pubkey;
        address[] maintainers;
        // EnumerableSet.AddressSet maintainerList;
    }

    //
    mapping(bytes32 => TSSInfo) private tssInfos;

    mapping(uint256 => bytes32) private epochKeys;

    // epoch => address => point
    mapping(uint256 => mapping(address => uint256)) private slashPoints;

    mapping(address => uint256) private jail;

    struct KeyShare {
        bytes pubkey;
        bytes keyShare;
    }

    mapping(address => KeyShare) private keyShares;

    struct Proposal {
        uint64 count;
        uint64 consensusBlock;
        mapping(address => bool) proposed;
    }

    mapping(bytes32 => Proposal) private proposals;

    IRelay public relay;
    IParameters public parameters;
    IMaintainers public maintainerManager;

    event VoteUpdateTssPool(TssPoolParam param);
    event ResetSlashPoint(address m);

    event VoteTxIn(TxInItem txInItem);
    event VoteTxOut(TxOutItem txOutItem);

    event Set(address _maintainer, address _relay, address _parameter);
    event UpdateKeyShare(address maitainer, bytes pubkey, bytes keyShare);
    event VoteNetworkFee(uint256 epoch, uint256 chain, uint256 height, uint256 limit, uint256 price);

    error no_access();
    error invalid_sig();
    error invalid_members();
    error already_propose();
    error invalid_status();

    modifier onlyMaintainers() {
        if (msg.sender != address(maintainerManager)) revert no_access();
        _;
    }

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function set(address _maintainer, address _relay, address _parameter) external restricted {
        require(_maintainer != address(0) && _parameter != address(0) && _relay != address(0));
        parameters = IParameters(_parameter);
        maintainerManager = IMaintainers(_maintainer);
        relay = IRelay(_relay);
        emit Set(_maintainer, _relay, _parameter);
    }

    function getTSSStatus(uint256 epochId) external view returns (TSSStatus) {
        bytes32 keyHash = epochKeys[epochId];

        TSSInfo storage e = tssInfos[keyHash];

        return e.status;
    }

    function elect(uint256 _epochId, address[] calldata _maintainers)
        external
        override
        onlyMaintainers
        returns (bool)
    {
        // todo: check status
        bytes32 keyHash = epochKeys[currentEpoch];
        TSSInfo storage currentTSS = tssInfos[keyHash];

        if (Utils.addressListEq(currentTSS.maintainers, _maintainers)) {
            // no need rotate
            epochKeys[_epochId] = activePubkey;
            currentTSS.epochId = _epochId;
            currentEpoch = _epochId;

            return false;
        }

        epochKeys[_epochId] = ELECTING_PUBKEY_HASH;
        TSSInfo storage e = tssInfos[ELECTING_PUBKEY_HASH];
        // voteUpdateTssPool time out reElect
        if (e.electBlock > 0) {
            _resetSlashPoint(_epochId, _maintainers);
        }
        e.electBlock = _getBlock();

        e.maintainers = _maintainers;
        e.epochId = _epochId;

        e.status = TSSStatus.KEYGEN_PENDING;
        // todo emit new election members

        return true;
    }

    function rotate(uint256 currentId, uint256 nextId) external override onlyMaintainers {
        currentEpoch = nextId;

        retirePubkey = epochKeys[currentId];
        activePubkey = epochKeys[nextId];

        currentId = nextId;

        TSSInfo storage retireEpoch = tssInfos[retirePubkey];
        TSSInfo storage activeEpoch = tssInfos[activePubkey];

        retireEpoch.status = TSSStatus.RETIRING;
        activeEpoch.status = TSSStatus.MIGRATING;

        _getRelay().rotate(retireEpoch.pubkey, activeEpoch.pubkey);
        // todo: emit event
    }

    function retire(uint256 retireEpochId, uint256 activeEpochId) external override onlyMaintainers {
        retirePubkey = epochKeys[retireEpochId];
        activePubkey = epochKeys[activeEpochId];

        TSSInfo storage retireTSS = tssInfos[retirePubkey];
        TSSInfo storage activeTSS = tssInfos[activePubkey];

        retireTSS.status = TSSStatus.RETIRED;
        activeTSS.status = TSSStatus.ACTIVE;

        // todo: emit event
    }

    function migrate() external override onlyMaintainers {
        bool completed = _getRelay().migrate();

        if (completed) {
            TSSInfo storage activeEpoch = tssInfos[activePubkey];
            if (activeEpoch.status == TSSStatus.MIGRATING) {
                activeEpoch.status = TSSStatus.MIGRATED;

                // todo: emit event
            }
        }
    }

    struct TssPoolParam {
        uint256 epoch;
        bytes pubkey;
        bytes keyShare;
        address[] members;
        address[] blames;
        bytes signature;
    }


    /**
     * This method generates a new TSS key after a epoch change.
     * If the blames array is empty, it indicates a keyGen failure.
     * Before consensus is reached, each committer first applies OBSERVE_SLASH_POINT.
     * After consensus is achieved, participants in the consensus revert the OBSERVE_SLASH_POINT applied before consensus was reached,
     * while non-participants apply DELAY_SLASH_POINT.
     * If non-participants submit within the specified block range, the DELAY_SLASH_POINT applied after consensus is reverted.
     * In case of keyGen failure, added jail block to users listed in the blames array.
     */
    function voteUpdateTssPool(TssPoolParam calldata param) external {
        address user = msg.sender;
        TSSInfo storage e = tssInfos[ELECTING_PUBKEY_HASH];
        _checkTssPoolStatus(param.epoch, e);

        _updateKeyShare(user, param.pubkey, param.keyShare);
        Proposal storage p = proposals[_getUpdateTSSPoolHash(param)];
        bool keyGen = (param.blames.length == 0);
        uint256 delaySlashPoint;
        if (keyGen) {
            delaySlashPoint = _getParameter(Constant.KEY_GEN_DELAY_SLASH_POINT);
        } else {
            // keyGen failed
            delaySlashPoint = _getParameter(Constant.OBSERVE_DELAY_SLASH_POINT);
        }
        _beforePropose(0, delaySlashPoint, user, p, e);
        if (keyGen) {
            if (!Utils.addressListEq(param.members, e.maintainers)) revert invalid_members();
            _checkSig(param.pubkey, param.signature);

            if (_consensus(p, e.maintainers.length)) {
                _handleConsensus(0, param.epoch, delaySlashPoint, p, e.maintainers);
            }
            // all members commit
            if (p.count == param.members.length) {
                bytes32 tssKey = keccak256(param.pubkey);

                epochKeys[param.epoch] = tssKey;

                TSSInfo storage te = tssInfos[tssKey];
                te.status = TSSStatus.KEYGEN_COMPLETED;

                te.pubkey = param.pubkey;
                te.threshold = uint64(param.members.length) * 2 / 3;
                //te.startBlock = _getBlock();
            }
        } else {
            // keyGen failed;
            if (_consensus(p, e.maintainers.length)) {
                // add blames to jail
                _batchAddToJail(param.blames, _getParameter(Constant.KEY_GEN_FAIL_JAIL_BLOCK));
                _handleConsensus(0, param.epoch, delaySlashPoint, p, e.maintainers);
            }

            e.status = TSSStatus.KEYGEN_FAILED;
        }

        emit VoteUpdateTssPool(param);
    }

    /**
     * This method is used to submit the gas fee status of various blockchains.
     * Before consensus is reached, each committer first applies OBSERVE_SLASH_POINT.
     * After consensus is achieved, participants in the consensus revert the OBSERVE_SLASH_POINT applied before consensus was reached,
     * while non-participants apply DELAY_SLASH_POINT.
     * If non-participants submit within the specified block range, the DELAY_SLASH_POINT applied after consensus is reverted.
     */
    function voteNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionRate,
        uint256 transactionSize,
        uint256 transactionSizeWithCall
    ) external {
        bytes32 hash = keccak256(
            abi.encodePacked(currentEpoch, chain, height, transactionRate, transactionSize, transactionSizeWithCall)
        );
        address user = msg.sender;
        TSSInfo storage e = tssInfos[activePubkey];
        Proposal storage p = proposals[hash];
        uint256 delaySlashPoint = _getParameter(Constant.OBSERVE_DELAY_SLASH_POINT);
        _beforePropose(0, delaySlashPoint, user, p, e);
        if (_consensus(p, e.maintainers.length)) {
            _getRelay().postNetworkFee(chain, height, transactionSize, transactionSizeWithCall, transactionRate);
            _handleConsensus(0, e.epochId, delaySlashPoint, p, e.maintainers);
        }
        emit VoteNetworkFee(currentEpoch, chain, height, transactionSize, transactionRate);
    }

    /**
     * This method processes transactions that cross over from other chains through consensus on the relay chain.
     * Before consensus is reached, each committer first applies OBSERVE_SLASH_POINT.
     * After consensus is achieved, participants in the consensus revert the OBSERVE_SLASH_POINT applied before consensus was reached,
     * while non-participants apply DELAY_SLASH_POINT.
     * If non-participants submit within the specified block range, the DELAY_SLASH_POINT applied after consensus is reverted.
     */
    function voteTxIn(TxInItem calldata txInItem) external {
        bytes32 hash = _getTxInItemHash(txInItem);
        address user = msg.sender;
        bytes32 tssKey = keccak256(txInItem.vault);
        TSSInfo storage e = tssInfos[tssKey];
        Proposal storage p = proposals[hash];
        uint256 delaySlashPoint = _getParameter(Constant.OBSERVE_DELAY_SLASH_POINT);
        _beforePropose(0, delaySlashPoint, user, p, e);
        if (_consensus(p, e.maintainers.length)) {
            _getRelay().executeTxIn(txInItem);
            _handleConsensus(0, e.epochId, delaySlashPoint, p, e.maintainers);
        }
        emit VoteTxIn(txInItem);
    }

    /**
     * This method consensus on the relay chain that the target chain has accurately executed the cross-chain transaction.
     * Before consensus is reached, each committer first applies OBSERVE_SLASH_POINT.
     * After consensus is achieved, participants in the consensus revert the OBSERVE_SLASH_POINT applied before consensus was reached,
     * while non-participants apply DELAY_SLASH_POINT.
     * If non-participants submit within the specified block range, the DELAY_SLASH_POINT applied after consensus is reverted.
     * if TxOutType is MIGRATE add jail block to users who non-participants submit within the specified block range.
     */
    function voteTxOut(TxOutItem calldata txOutItem) external {
        bytes32 hash = _getTxOutItemHash(txOutItem);
        address user = msg.sender;
        bytes32 tssKey = keccak256(txOutItem.vault);
        TSSInfo storage e = tssInfos[tssKey];
        Proposal storage p = proposals[hash];
        uint256 delaySlashPoint;
        uint256 jailBlock;
        if (txOutItem.txOutType == TxType.MIGRATE) {
            delaySlashPoint = _getParameter(Constant.MIGRATION_DELAY_SLASH_POINT);
            jailBlock = _getParameter(Constant.MIGRATION_DELAY_JAIL_BLOCK);
        } else {
            delaySlashPoint = _getParameter(Constant.OBSERVE_DELAY_SLASH_POINT);
        }
        _beforePropose(jailBlock, delaySlashPoint, user, p, e);
        if (_consensus(p, e.maintainers.length)) {
            p.consensusBlock = _getBlock();
            _getRelay().executeTxOut(txOutItem);
            _handleConsensus(jailBlock, e.epochId, delaySlashPoint, p, e.maintainers);
        }
        emit VoteTxOut(txOutItem);
    }

    function getSlashPoint(uint256 epoch, address m) external view override returns (uint256 point) {
        point = slashPoints[epoch][m];
    }

    function getJailBlock(address m) external view override returns (uint256 jailBlock) {
        jailBlock = jail[m];
    }

    function batchGetSlashPoint(uint256 epoch, address[] calldata ms)
        external
        view
        override
        returns (uint256[] memory points)
    {
        uint256 len = ms.length;
        points = new uint256[](len);
        for (uint256 i = 0; i < len;) {
            points[i] = slashPoints[epoch][ms[i]];
            unchecked {
                ++i;
            }
        }
    }

    function _updateKeyShare(address _maintainer, bytes calldata _pubkey, bytes calldata _keyShare) internal {
        if (_pubkey.length > 0 && _keyShare.length > 0) {
            KeyShare storage ks = keyShares[_maintainer];
            ks.keyShare = _keyShare;
            ks.pubkey = _pubkey;
            emit UpdateKeyShare(_maintainer, _pubkey, _keyShare);
        }
    }

    function _getMaintainer() internal view returns (IMaintainers m) {
        return maintainerManager;
    }

    function _getRelay() internal view returns (IRelay r) {
        return relay;
    }

    function _beforePropose(
        uint256 jailBlock,
        uint256 delayRecoverPoint,
        address maintainer,
        Proposal storage p,
        TSSInfo storage e
    ) internal {
        if (!Utils.addressListContains(e.maintainers, maintainer)) {
            revert no_access();
        }
        if (p.proposed[maintainer]) revert already_propose();
        p.proposed[maintainer] = true;
        p.count += 1;
        if (p.consensusBlock == 0) {
            // apply OBSERVE_SLASH_POINT before Consensus.
            _addSlashPoint(e.epochId, maintainer, _getParameter(Constant.OBSERVE_SLASH_POINT));
        } else {
            if ((_getParameter(Constant.OBSERVE_MAX_DELAY_BLOCK) + p.consensusBlock) > _getBlock()) {
                // non-participants submit within the specified block range,
                // reverted the DELAY_SLASH_POINT applied after consensus.
                _subSlashPoint(e.epochId, maintainer, delayRecoverPoint);
                if (jailBlock > 0) _releaseFromJail(maintainer, jailBlock);
            }
        }
    }

    function _handleConsensus(
        uint256 jailBlock,
        uint256 epochId,
        uint256 delaySlashPoint,
        Proposal storage p,
        address[] memory maintainers
    ) internal {
        p.consensusBlock = _getBlock();
        uint256 len = maintainers.length;
        // maintainers submitted propose before Consensus
        address[] memory subs = new address[](p.count);
        // maintainers no-submitted propose before Consensus
        address[] memory adds = new address[](len - p.count);
        uint256 index;
        for (uint256 i = 0; i < len;) {
            address a = maintainers[i];
            if (p.proposed[a]) {
                subs[index] = a;
                ++index;
            } else {
                adds[i - index] = a;
            }
            unchecked {
                ++i;
            }
        }
        // revert the OBSERVE_SLASH_POINT applied before consensus was reached
        _batchSubSlashPoint(epochId, subs, _getParameter(Constant.OBSERVE_SLASH_POINT));
        // non-participants apply DELAY_SLASH_POINT.
        _batchAddSlashPoint(epochId, adds, delaySlashPoint);
        if (jailBlock > 0) _batchAddToJail(adds, jailBlock);
    }

    function _checkSig(bytes calldata pubkey, bytes calldata signature) internal pure {
        if (pubkey.length != 64) revert invalid_sig();
        bytes32 pubkeyHash = keccak256(pubkey);
        address signer = ECDSA.recover(pubkeyHash, signature);
        if (signer != _publicKeyHashToAddress(pubkeyHash)) revert invalid_sig();
    }

    function _publicKeyHashToAddress(bytes32 pubkeyHash) public pure returns (address) {
        return address(uint160(uint256(pubkeyHash)));
    }

    function _consensus(Proposal storage p, uint256 maintainerCount) internal view returns (bool) {
        return p.consensusBlock == 0 && (p.count > ((maintainerCount * 2) / 3));
    }

    function _getUpdateTSSPoolHash(TssPoolParam calldata param) internal pure returns (bytes32 hash) {
        hash = keccak256(abi.encodePacked(param.pubkey, param.members, param.epoch, param.blames));
    }

    function _getTxInItemHash(TxInItem calldata txInItem) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                txInItem.txInType,
                txInItem.orderId,
                txInItem.chainAndGasLimit,
                txInItem.height,
                txInItem.token,
                txInItem.amount,
                txInItem.from,
                txInItem.vault,
                txInItem.to
            )
        );
    }

    function _getTxOutItemHash(TxOutItem calldata txOutItem) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                txOutItem.txOutType,
                txOutItem.orderId,
                txOutItem.chainAndGasLimit,
                txOutItem.height,
                txOutItem.gasUsed,
                txOutItem.sequence,
                txOutItem.sender,
                txOutItem.to,
                txOutItem.vault
            )
        );
    }

    function _batchAddToJail(address[] memory ms, uint256 jailBlock) internal {
        uint256 len = ms.length;
        uint128 b = _getBlock();
        for (uint256 i = 0; i < len;) {
            uint256 j = jail[ms[i]];
            uint256 add = j > b ? j : b;
            jail[ms[i]] = add + jailBlock;
            unchecked {
                ++i;
            }
        }
    }

    function _releaseFromJail(address m, uint256 jailBlock) internal {
        jail[m] -= jailBlock;
    }

    function _batchAddSlashPoint(uint256 _epochId, address[] memory _maintainers, uint256 _point) internal {
        uint256 len = _maintainers.length;
        for (uint256 i = 0; i < len;) {
            address m = _maintainers[i];
            _addSlashPoint(_epochId, m, _point);
            unchecked {
                ++i;
            }
        }
    }

    function _batchSubSlashPoint(uint256 _epochId, address[] memory _maintainers, uint256 _point) internal {
        uint256 len = _maintainers.length;
        for (uint256 i = 0; i < len;) {
            address m = _maintainers[i];
            _subSlashPoint(_epochId, m, _point);
            unchecked {
                ++i;
            }
        }
    }

    function _addSlashPoint(uint256 _epochId, address _maintainer, uint256 _point) internal {
        slashPoints[_epochId][_maintainer] += _point;
    }

    function _subSlashPoint(uint256 _epochId, address _maintainer, uint256 _point) internal {
        if (slashPoints[_epochId][_maintainer] > _point) {
            slashPoints[_epochId][_maintainer] -= _point;
        } else {
            slashPoints[_epochId][_maintainer] = 0;
        }
    }

    function _resetSlashPoint(uint256 epoch, address[] memory ms) internal {
        uint256 len = ms.length;
        for (uint256 i = 0; i < len;) {
            address m = ms[i];
            slashPoints[epoch][m] = 0;
            unchecked {
                ++i;
            }
        }
    }

    function _checkTssPoolStatus(uint256 epoch, TSSInfo storage e) internal view {
        if (epochKeys[epoch] != ELECTING_PUBKEY_HASH) revert invalid_status();
        if ((e.electBlock + _getParameter(Constant.MAX_BLOCKS_FOR_UPDATE_TSS)) < _getBlock()) revert invalid_status();
    }

    function _getParameter(bytes32 hash) internal view returns (uint256) {
        return parameters.getByHash(hash);
    }

    function _getBlock() internal view returns (uint64) {
        return uint64(block.number);
    }
}
