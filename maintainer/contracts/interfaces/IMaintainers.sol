// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMaintainers {
    enum MaintainerStatus {
        UNKNOWN,
        REVOKED,
        STANDBY, // waiting to participate tss
        READY, // selected, the new tss member
        ACTIVE, // current tss member
        DISABLED
    }

    enum ElectionStatus {
        NONE,
        SCHEDULED,
        IN_PROGRESS,
        COMPLETED,
        INIT // waiting for tss setup

    }

    struct MaintainerInfo {
        MaintainerStatus status;
        address account;
        uint256 lastActiveEpoch;
        bytes secp256Pubkey;
        bytes ed25519Pubkey;
        string p2pAddress;
    }

    struct EpochInfo {
        uint64 electedBlock;
        uint64 startBlock;
        uint64 endBlock;
        uint64 migratedBlock;
        address[] maintainers;
    }

    function distributeReward() external payable;

    function orchestrate() external;

    function register(bytes calldata secp256Pubkey, bytes calldata ed25519PubKey, string calldata p2pAddress) external;
    function update(bytes calldata secp256Pubkey, bytes calldata ed25519PubKey, string calldata p2pAddress) external;
    function revoke() external;
    function deregister() external;
    function getMaintainerInfos(address[] calldata ms) external view returns(MaintainerInfo[] memory infos);
    function getEpochInfo(uint256 epochId) external view returns(EpochInfo memory info);
    // function onKeyGenCompleted(bool success, bytes32 publicKeyHash) external;
    // function onRotationCompleted(bool success) external;
}
