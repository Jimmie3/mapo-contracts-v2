// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IMaintainers } from "./interfaces/IMaintainers.sol";
import { IValidators } from "./interfaces/IValidators.sol";
import { IElection } from "./interfaces/IElection.sol";
import { IAccounts } from "./interfaces/IAccounts.sol";
import { ITSSManager } from "./interfaces/ITSSManager.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract Maintainers is BaseImplementation, IMaintainers {
    address public constant ACCOUNTS_ADDRESS = 0xEBf2c3d4FC8e8314609f26e3F48709f3C4746B67;
    address public constant VALIDATORS_ADDRESS = 0x48F6678000cB44f746ea6C409f0f7beD33a6Ab48;
    address public constant ELECTIONS_ADDRESS = 0x3c21D9371D987B1f4aC26bA08ae62952C3f03D9b;
    string public constant version = "1.0.0";

    uint256 private constant BLOCKS_PER_EPOCH = 50_000;
    uint256 private constant MAX_BLOCKS_FOR_UPDATE_TSS = 5000;

    uint256 public currentEpoch;
    uint256 public electionEpoch;

    uint256 public rotationAttempts;
    uint256 constant MAX_RETRY = 3;

    uint256 public maintainerLimit = 3;

    ITSSManager public tssManager;

    mapping(address => bytes) private keyShare;

    mapping(address => MaintainerInfo) private maintainerInfos;

    mapping(uint256 => EpochInfo) private epochInfos;

    error no_access();
    error empty_pubkey();
    error empty_p2pAddress();
    error maintainer_not_enough();
    error only_validator_can_register();

    event Deregister(address user);
    event SetTSSManager(address manager);
    event UpdateKeyShare(address maitainer, bytes keyShare);
    event UpdateMaintainerLimit(uint256 limit);
    event Update(address user, bytes secp256Pubkey, bytes ed25519PubKey, string p2pAddress);
    event Register(address user, bytes secp256Pubkey, bytes ed25519PubKey, string p2pAddress);

    modifier onlyTSSManager() {
        if (msg.sender != address(tssManager)) revert no_access();
        _;
    }

    modifier onlyVm() {
        //if (msg.sender != address(0)) revert no_access();
        _;
    }

    receive() external payable { }

    function setTSSManager(address _manager) external restricted {
        require(_manager != address(0));
        tssManager = ITSSManager(_manager);
        emit SetTSSManager(_manager);
    }

    function updateMaintainerLimit(uint256 _limit) external restricted {
        require(_limit > 3 && _limit < 30);
        maintainerLimit = _limit;
        emit UpdateMaintainerLimit(_limit);
    }

    function register(
        bytes calldata secp256Pubkey,
        bytes calldata ed25519PubKey,
        string calldata p2pAddress
    )
        external
        restricted
    {
        address user = msg.sender;
        MaintainerInfo storage info = maintainerInfos[user];
        // require(info.status == MaintainerStatus.UNKNOWN);
        if (secp256Pubkey.length == 0 || ed25519PubKey.length == 0) {
            revert empty_pubkey();
        }
        if (bytes(p2pAddress).length == 0) revert empty_p2pAddress();
        if (!_isValidator(user)) revert only_validator_can_register();
        info.status = MaintainerStatus.STANDBY;
        info.p2pAddress = p2pAddress;
        info.secp256Pubkey = secp256Pubkey;
        info.ed25519Pubkey = ed25519PubKey;
        info.account = user;
        emit Register(user, secp256Pubkey, ed25519PubKey, p2pAddress);
    }

    function update(
        bytes calldata secp256Pubkey,
        bytes calldata ed25519PubKey,
        string calldata p2pAddress
    )
        external
    {
        address user = msg.sender;
        MaintainerInfo storage info = maintainerInfos[user];
        require(info.status == MaintainerStatus.STANDBY);
        if (secp256Pubkey.length == 0 || ed25519PubKey.length == 0) {
            revert empty_pubkey();
        }
        if (bytes(p2pAddress).length == 0) revert empty_p2pAddress();
        info.p2pAddress = p2pAddress;
        info.secp256Pubkey = secp256Pubkey;
        info.ed25519Pubkey = ed25519PubKey;
        emit Update(user, secp256Pubkey, ed25519PubKey, p2pAddress);
    }

    // will not participate tss
    function revoke() external {
        // todo


    }

    function deregister() external {
        address user = msg.sender;
        MaintainerInfo storage info = maintainerInfos[user];
        require(info.status == MaintainerStatus.STANDBY);
        require(info.lastActiveEpoch == 0 || (info.lastActiveEpoch + 1) < currentEpoch);
        delete maintainerInfos[user];
        emit Deregister(user);
    }

    function orchestrate() external {
        if (electionEpoch == 0) {
            ITSSManager.TSSStatus status = tssManager.getTSSStatus(currentEpoch);
            EpochInfo storage epoch = epochInfos[currentEpoch];
            if (status == ITSSManager.TSSStatus.ACTIVE && (epoch.startBlock + BLOCKS_PER_EPOCH < block.number)) {
                // todo rotate to new epoch
                // slash
                // incentive
                // election
                _elect();
            } else {
                tssManager.migrate();
            }
        } else {
            ITSSManager.TSSStatus status = tssManager.getTSSStatus(electionEpoch);
            EpochInfo storage epoch = epochInfos[electionEpoch];
            if (status == ITSSManager.TSSStatus.KEYGEN_FAILED ||
                (status == ITSSManager.TSSStatus.KEYGEN_PENDING && (epoch.electedBlock + MAX_BLOCKS_FOR_UPDATE_TSS < block.number))) {

                _switchMaintainerStatus(epoch.maintainers, MaintainerStatus.ACTIVE, MaintainerStatus.STANDBY);
                // todo: slash and re-elect maintainers
                _elect();

            } else if (status == ITSSManager.TSSStatus.KEYGEN_COMPLETED) {
                _switchMaintainerStatus(epoch.maintainers, MaintainerStatus.ACTIVE, MaintainerStatus.ACTIVE);
                // finish tss keygen, start migration
                tssManager.rotate(currentEpoch, electionEpoch);
                EpochInfo storage e = epochInfos[currentEpoch];
                e.endBlock = uint64(block.number);
                epoch.startBlock = uint64(block.number);
            } else if (status == ITSSManager.TSSStatus.MIGRATED) {
                //
                tssManager.rotate(currentEpoch, electionEpoch);
                EpochInfo storage retireEpoch = epochInfos[currentEpoch];
                currentEpoch = electionEpoch;
                electionEpoch = 0;
                retireEpoch.migratedBlock = uint64(block.number);

                _switchMaintainerStatus(retireEpoch.maintainers, MaintainerStatus.ACTIVE, MaintainerStatus.STANDBY);
                _switchMaintainerStatus(epoch.maintainers, MaintainerStatus.ACTIVE, MaintainerStatus.STANDBY);
            }
        }
    }

    function _elect() internal {
        if (electionEpoch == 0) electionEpoch = currentEpoch + 1;

        address[] memory maintainers = _chooseMaintainers();

        EpochInfo storage e = epochInfos[electionEpoch];
        e.electedBlock = uint64(block.number);
        e.maintainers = maintainers;

        tssManager.elect(electionEpoch, maintainers);
        _switchMaintainerStatus(maintainers, MaintainerStatus.ACTIVE, MaintainerStatus.READY);
        // todo: emit epoch info
    }

    function distributeReward() external override payable onlyVm { }

    function updateKeyShare(
        address _maintainer,
        bytes calldata _keyShare
    )
        external
        override
        onlyTSSManager
    {
        keyShare[_maintainer] = _keyShare;
        emit UpdateKeyShare(_maintainer, _keyShare);
    }


    function _switchMaintainerStatus(address[] memory maintainers, MaintainerStatus keep, MaintainerStatus target) internal {
        uint256 len = maintainers.length;
        for (uint256 i = 0; i < len; ) {
            MaintainerInfo storage info = maintainerInfos[maintainers[i]];
            if (info.status != keep) info.status = target;
            unchecked {
                ++i;
            }
        }
    }

    function _chooseMaintainers() internal view returns (address[] memory maintainers) {
        address[] memory validators = _getCurrentValidatorSigners();
        uint256 length = validators.length;
        uint256 selectedCount = maintainerLimit;
        maintainers = new address[](selectedCount);
        for (uint256 i = 0; i < length;) {
            address validator = validators[i];
            MaintainerStatus status = maintainerInfos[validator].status;
            if (status == MaintainerStatus.STANDBY || status == MaintainerStatus.ACTIVE) {
                maintainers[i] = validator;
                if ((selectedCount -= 1) == 0) break;
            }
            unchecked {
                ++i;
            }
        }
        if (selectedCount != 0) revert maintainer_not_enough();
    }

    function _getCurrentValidatorSigners() internal view returns (address[] memory signers) {
        signers = IElection(ELECTIONS_ADDRESS).getCurrentValidatorSigners();
    }

    function _isValidator(address _user) internal view returns (bool) {
        address account = IAccounts(ACCOUNTS_ADDRESS).signerToAccount(_user);
        return IValidators(VALIDATORS_ADDRESS).isValidator(account);
    }

}
