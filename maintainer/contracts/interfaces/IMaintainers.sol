// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMaintainers {
    enum MaintainerStatus {
        UNKNOWN,    // initial state
        REVOKED,    // revoked by system
        STANDBY,    // waiting to participate tss
        READY,      // selected, the new tss member
        ACTIVE,     // current tss member
        JAILED,     // jailed due to misbehavior
        REGISTERED  // registered but not activated
    }

    struct MaintainerInfo {
        MaintainerStatus status;            // current status of the maintainer
        address account;                    // maintainer account address
        uint256 lastHeartbeatTime;          // timestamp of last heartbeat
        uint256 lastActiveEpoch;            // last epoch the maintainer was active
        bytes secp256Pubkey;                // secp256k1 public key, keccak256 hash derives to account address
        bytes ed25519Pubkey;                // ed25519 public key for TSS protocol operations
        string p2pAddress;                  // p2p network address for node communication
    }

    struct EpochInfo {
        uint64 electedBlock;                // block number when maintainers were elected
        uint64 startBlock;                  // block number when epoch started (TSS keygen completed)
        uint64 endBlock;                    // block number when epoch ended (next epoch started)
        uint64 migratedBlock;               // block number when migration completed (assets transferred to new TSS)
        address[] maintainers;              // list of maintainer addresses for this epoch
    }

    /// @notice Distribute rewards to maintainers for the epoch
    function distributeReward() external payable;

    /// @notice Orchestrate the election and migration process
    function orchestrate() external;

    /// @notice Register a new maintainer (called by validator)
    /// @dev Status: UNKNOWN -> REGISTERED
    ///      Requirements:
    ///      - maintainerAddr must not be zero address
    ///      - maintainerAddr must not be already registered
    ///      - caller must be a validator
    ///      - secp256Pubkey and ed25519PubKey must not be empty
    ///      - p2pAddress must not be empty
    ///      - keccak256(secp256Pubkey) must derive to maintainerAddr
    ///      Errors:
    ///      - `empty_pubkey`: secp256Pubkey or ed25519PubKey is empty
    ///      - `empty_p2pAddress`: p2pAddress is empty
    ///      - `invalid_pubkey`: secp256Pubkey does not match maintainerAddr
    ///      - `only_validator_can_register`: caller is not a validator
    /// @param maintainerAddr The maintainer account address (required, non-zero)
    /// @param secp256Pubkey The secp256k1 public key corresponding to maintainerAddr (required, used for signature verification)
    /// @param ed25519PubKey The ed25519 public key for TSS operations (required, used in TSS protocol)
    /// @param p2pAddress The p2p network address for node communication (required)
    function register(address maintainerAddr, bytes calldata secp256Pubkey, bytes calldata ed25519PubKey, string calldata p2pAddress) external;

    /// @notice Deregister a maintainer (called by validator)
    /// @dev Status: REGISTERED -> deleted
    function deregister() external;

    /// @notice Update maintainer info (called by validator)
    /// @dev Status: REGISTERED -> STANDBY
    ///      Requirements:
    ///      - maintainerAddr must not be zero address
    ///      - caller's maintainer status must be REGISTERED
    ///      - lastActiveEpoch must be 0 or less than currentEpoch
    ///      - secp256Pubkey and ed25519PubKey must not be empty
    ///      - p2pAddress must not be empty
    ///      - keccak256(secp256Pubkey) must derive to maintainerAddr
    ///      Errors:
    ///      - `empty_pubkey`: secp256Pubkey or ed25519PubKey is empty
    ///      - `empty_p2pAddress`: p2pAddress is empty
    ///      - `invalid_pubkey`: secp256Pubkey does not match maintainerAddr
    /// @param maintainerAddr The new maintainer account address (required, non-zero)
    /// @param secp256Pubkey The secp256k1 public key corresponding to maintainerAddr (required, used for signature verification)
    /// @param ed25519PubKey The ed25519 public key for TSS operations (required, used in TSS protocol)
    /// @param p2pAddress The p2p network address for node communication (required)
    function update(address maintainerAddr, bytes calldata secp256Pubkey, bytes calldata ed25519PubKey, string calldata p2pAddress) external;

    /// @notice Activate the maintainer to participate in election (called by maintainer)
    /// @dev Status: REGISTERED -> STANDBY
    function activate() external;

    /// @notice Revoke the maintainer from election candidacy (called by maintainer)
    /// @dev Status: STANDBY/READY/ACTIVE -> REGISTERED
    function revoke() external;


    /// @notice Jail misbehaving maintainers (called by TSSManager)
    /// @param maintainers Array of maintainer addresses to jail
    function jail(address[] calldata maintainers) external;

    /// @notice Get maintainer info for multiple addresses
    /// @param ms Array of maintainer addresses
    /// @return infos Array of MaintainerInfo structs
    function getMaintainerInfos(address[] calldata ms) external view returns(MaintainerInfo[] memory infos);

    /// @notice Get epoch info by epoch id
    /// @param epochId The epoch id (0 for current epoch)
    /// @return info The EpochInfo struct
    function getEpochInfo(uint256 epochId) external view returns(EpochInfo memory info);

}