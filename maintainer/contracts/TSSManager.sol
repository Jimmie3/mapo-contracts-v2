// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Utils } from "./libs/Utils.sol";
import { Constant } from "./libs/Constant.sol";
import { ITSSManager } from "./interfaces/ITSSManager.sol";
import { IRelay } from "./interfaces/IRelay.sol";
import { IMaintainers } from "./interfaces/IMaintainers.sol";
import { TxInItem, TxOutItem, TxOutType } from "./libs/Types.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract TSSManager is BaseImplementation, ITSSManager {
    uint256 private constant MIN_BLOCKS_PER_EPOCH = 50_000;
    uint256 private constant MAX_BLOCKS_FOR_UPDATE_TSS = 5000;

    bytes32 private constant ELECTING_PUBKEY_HASH = 0x0000000000000000000000000000000000000000000000000000000000000001;       // electing epoch hasn't gen tss key

    bytes32 private activePubkey;
    bytes32 private retirePubkey;

    uint256 public currentEpoch;

    struct TSSInfo {
        TSSStatus status;
        uint256 epochId;
        uint128 electBlock;
        uint128 startBlock;
        uint128 endBlock;
        uint128 migrateBlock;
        bytes pubkey;
        address[] maintainers;
    }

    //
    mapping(bytes32 => TSSInfo) private tssInfos;

    mapping(uint256 => bytes32) private epochKeys;

    mapping(address => uint256) private slashPoints;

    struct KeyShare {
        bytes pubkey;
        bytes keyShare;
    }

    mapping(address => KeyShare) private keyShares;

    struct Propose {
        uint128 count;
        uint128 consensusBlock;
        mapping(address => bool) proposed;
    }

    mapping(bytes32 => Propose) private proposes;

    IMaintainers public maintainerManager;
    IRelay public relay;

    event VoteUpdateTssPool(TssPoolParam param);
    event ResetSlashPoint(address m);
    event VoteTxIn(TxInItem txInItem);
    event VoteTxOut(TxOutItem txOutItem);
    event UpdateKeyShare(address maitainer, bytes pubkey, bytes keyShare);
    event VoteNetworkFee(
        uint256 epoch, uint256 chain, uint256 height, uint256 limit, uint256 price
    );

    error no_access();
    error invalid_sig();
    error invalid_members();
    error already_propose();
    error invalid_status();
    error invalid_tss_pool_id();

    modifier onlyMaintainers() {
        if(msg.sender != address(maintainerManager)) revert no_access();
        _;
    }

    function getTSSStatus(uint256 epochId) external view returns (TSSStatus) {
        bytes32 keyHash = epochKeys[epochId];

        TSSInfo storage e = tssInfos[keyHash];

        return e.status;
    }

    function elect(uint256 _epochId, address[] calldata _maintainers) external override onlyMaintainers returns (bool) {
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

        _getRelay().rotate(retirePubkey, activePubkey);
    }

    function retire(uint256 epochId, uint256 newId) external override onlyMaintainers {
        retirePubkey = epochKeys[epochId];
        activePubkey = epochKeys[newId];

        TSSInfo storage retireTSS = tssInfos[retirePubkey];
        TSSInfo storage activeTSS = tssInfos[activePubkey];

        retireTSS.status = TSSStatus.RETIRED;
        activeTSS.status = TSSStatus.ACTIVE;
    }


    function migrate() external override onlyMaintainers {
        bool completed = _getRelay().migrate();

        TSSInfo storage activeEpoch = tssInfos[activePubkey];
        if (activeEpoch.status == TSSStatus.MIGRATING && completed) {
            activeEpoch.status = TSSStatus.MIGRATED;
        }
    }

    function resetSlashPoint(address m) external override onlyMaintainers {
        slashPoints[m] = 0;
        emit ResetSlashPoint(m);
    } 

    struct TssPoolParam {
        bytes32 id;
        uint256 epoch;
        bytes pubkey;
        bytes keyShare;
        address[] members;
        address[] blames;
        bytes signature;
    }

    function voteUpdateTssPool(TssPoolParam calldata param) external {
        if (epochKeys[param.epoch] != ELECTING_PUBKEY_HASH) revert invalid_status();
        TSSInfo storage e = tssInfos[ELECTING_PUBKEY_HASH];
        if ((e.electBlock + MAX_BLOCKS_FOR_UPDATE_TSS) < block.number) revert invalid_status();
        bytes32 id = getTSSPoolId(param.pubkey, param.members, param.epoch, param.blames);
        if (id != param.id) revert invalid_tss_pool_id();
        address user = msg.sender;
        Propose storage p = proposes[param.id];
        if (param.keyShare.length > 0) {
            _updateKeyShare(user, param.pubkey, param.keyShare);
        }
        _beforePropose(Constant.KEY_GEN_DELAY_SLASY_POINT, user, p, e);
        address[] memory blames = param.blames;
        if (blames.length == 0) {
            if (!Utils.addressListEq(param.members, e.maintainers)) revert invalid_members();
            _checkSig(param.pubkey, param.signature);

            if (_consensus(p, e.maintainers.length)) {
                p.consensusBlock = _getBlock();
                _dealProposedSlashPoint(param.epoch, Constant.KEY_GEN_DELAY_SLASY_POINT, p, e.maintainers);
            }
            // all members commit
            if (p.count == param.members.length) {

                bytes32 tssKey = keccak256(param.pubkey);

                epochKeys[param.epoch] = tssKey;

                TSSInfo storage te = tssInfos[tssKey];
                te.status = TSSStatus.KEYGEN_COMPLETED;

                te.pubkey = param.pubkey;
                te.startBlock = _getBlock();
            }
            // keyGen failed;
        } else {
            if (_consensus(p, e.maintainers.length)) {
                p.consensusBlock = _getBlock();
                // add blames slash point
                _batchAddSlashPoint(param.epoch, blames, Constant.KEY_GEN_FAIL_SLASH_POINT);

                _dealProposedSlashPoint(param.epoch, Constant.OBSERVE_DELAY_SLASH_POINT, p, e.maintainers);
            }

            e.status = TSSStatus.KEYGEN_FAILED;
        }
        emit VoteUpdateTssPool(param);
    }

    function getTSSPoolId(
        bytes calldata pubkey,
        address[] calldata members,
        uint256 epoch,
        address[] calldata blames
    )
        public
        pure
        returns (bytes32 id)
    {
        id = keccak256(abi.encodePacked(pubkey, members, epoch, blames));
    }

    // todo: add vaultKey?
    function voteNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionRate,
        uint256 transactionSize,
        uint256 transactionSizeWithCall
    )
        external
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                currentEpoch,
                chain,
                height,
                transactionRate,
                transactionSize,
                transactionSizeWithCall
            )
        );
        address user = msg.sender;
        TSSInfo storage e = tssInfos[activePubkey];
        Propose storage p = proposes[hash];
        _beforePropose(Constant.OBSERVE_DELAY_SLASH_POINT, user, p, e);
        if (_consensus(p, e.maintainers.length)) {
            p.consensusBlock = _getBlock();
            _getRelay().postNetworkFee(
                chain, height, transactionSize, transactionSizeWithCall, transactionRate
            );
            _dealProposedSlashPoint(e.epochId, Constant.OBSERVE_DELAY_SLASH_POINT, p, e.maintainers);
        }
        emit VoteNetworkFee(currentEpoch, chain, height, transactionSize, transactionRate);
    }

    function voteTxIn(TxInItem calldata txInItem) external {
        bytes32 hash = _getTxInItemHash(txInItem);
        address user = msg.sender;
        bytes32 tssKey = keccak256(txInItem.vault);
        TSSInfo storage e = tssInfos[tssKey];
        Propose storage p = proposes[hash];
        _beforePropose(Constant.OBSERVE_DELAY_SLASH_POINT, user, p, e);
        if (_consensus(p, e.maintainers.length)) {
            p.consensusBlock = _getBlock();
            _getRelay().executeTxIn(txInItem);
            _dealProposedSlashPoint(e.epochId, Constant.OBSERVE_DELAY_SLASH_POINT, p, e.maintainers);
        }
        emit VoteTxIn(txInItem);
    }

    function voteTxOut(TxOutItem calldata txOutItem) external {
        bytes32 hash = _getTxOutItemHash(txOutItem);
        address user = msg.sender;
        bytes32 tssKey = keccak256(txOutItem.vault);
        TSSInfo storage e = tssInfos[tssKey];
        Propose storage p = proposes[hash];
        _beforePropose(Constant.OBSERVE_DELAY_SLASH_POINT, user, p, e);
        if (_consensus(p, e.maintainers.length)) {
            p.consensusBlock = _getBlock();
            _getRelay().executeTxOut(txOutItem);
            uint256 delaySlashPoint = txOutItem.txOutType == TxOutType.TRANSFER ? Constant.OBSERVE_DELAY_SLASH_POINT : Constant.MIGRATION_DELAY_SLASH_POINT;
            _dealProposedSlashPoint(e.epochId, delaySlashPoint, p, e.maintainers);
        }
        emit VoteTxOut(txOutItem);
    }

    function _updateKeyShare(
        address _maintainer,
        bytes calldata _pubkey,
        bytes calldata _keyShare
    )
        internal
    {   
        KeyShare storage ks = keyShares[_maintainer];
        ks.keyShare = _keyShare;
        ks.pubkey = _pubkey;
        emit UpdateKeyShare(_maintainer, _pubkey, _keyShare);
    }

    function _getMaintainer() internal view returns (IMaintainers m) {
        return maintainerManager;
    }

    function _getRelay() internal view returns (IRelay r) {
        return relay;
    }

    function _beforePropose(
        uint256 delay_recover_point,
        address maintainer,
        Propose storage p,
        TSSInfo storage e
    )
        internal
    {
        if (!Utils.addressListContains(e.maintainers, maintainer)) {
            revert no_access();
        }
        if (p.proposed[maintainer]) revert already_propose();
        p.proposed[maintainer] = true;
        p.count += 1;
        // slash points
        if (p.consensusBlock == 0) {
            _addSlashPoint(e.epochId, maintainer, Constant.OBSERVE_SLASH_POINT);
        } else {
            if((Constant.MAX_DELYA_BLOCK + p.consensusBlock) < _getBlock()) {
                _subSlashPoint(maintainer, delay_recover_point);
                address[] memory ms = new address[](1);
                ms[0] = maintainer;
                _addScore(e.epochId, ms, Constant.VOTE_TX_DELAY_SCORE);
            }
        }
    }

    function _dealProposedSlashPoint(
        uint256 epochId,
        uint256 delaySlashPoint,
        Propose storage p,
        address[] memory maintainers
    )
        internal
    {    
        uint256 len = maintainers.length;
        address[] memory subs = new address[](p.count);
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
        _batchSubSlashPoint(subs, Constant.OBSERVE_SLASH_POINT);
        _addScore(epochId, subs, Constant.VOTE_TX_SCORE);
        if(adds.length > 0) {
            _batchAddSlashPoint(epochId, adds, delaySlashPoint);
        }
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

    function _consensus(
        Propose storage p,
        uint256 maintainerCount
    )
        internal
        view
        returns (bool)
    {    
        return p.consensusBlock == 0 && (p.count > ((maintainerCount * 2) / 3));
    }

    function _getTxInItemHash(TxInItem calldata txInItem) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                txInItem.txInType,
                txInItem.orderId,
                txInItem.chain,
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
                txOutItem.height,
                txOutItem.chain,
                txOutItem.gasUsed,
                txOutItem.sequence,
                txOutItem.sender,
                txOutItem.to,
                txOutItem.vault
            )
        );
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

    function _batchSubSlashPoint(
        address[] memory _maintainers,
        uint256 _point
    ) internal
    {
        uint256 len = _maintainers.length;
        for (uint256 i = 0; i < len; i++) {
            address m = _maintainers[i];
            _subSlashPoint(m, _point);
            unchecked {
                ++i;
            }
        }
    }

    function _addSlashPoint(uint256 _epochId, address _maintainer, uint256 _point) internal {
        slashPoints[_maintainer] += _point;

        uint256 totalPoint = slashPoints[_maintainer];
        if(totalPoint > Constant.JAIL_SLASH_LIMIT) {
            // add to jail
            maintainerManager.addToJail(_epochId, _maintainer, totalPoint);
        }
    }

    function _subSlashPoint(address _maintainer, uint256 _point) internal {
        if(slashPoints[_maintainer] > _point) {
            slashPoints[_maintainer] -= _point;
        } else {
            slashPoints[_maintainer] = 0;
        }

    }

    function _addScore(uint256 _epochId, address[] memory _maintainers, uint256 _score) internal {
        maintainerManager.addScore(_epochId, _maintainers, _score);
    }

    function _getBlock() internal view returns(uint128) {
        return uint128(block.number);
    }

}
