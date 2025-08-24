// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import { ManagerStatus } from "../libs/Types.sol";

interface ITSSManager {

    enum TSSStatus {
        UNKNOWN,
        KEYGEN_PENDING,     // tss keygen
        KEYGEN_COMPLETED,   // rotate to next epoch
        KEYGEN_FAILED,      // tss keygen failed

        MIGRATING,
        MIGRATED,           // complete the migration
        RETIRING,           // rotate to next epoch
        RETIRED,            //

        ACTIVE,

        EMERGENCY_PAUSE     //
    }


    function elect(uint256 _epochId, address[] calldata maintainers) external returns (uint256 epoch);

    function rotate(uint256 epochId, uint256 newId) external;

    function retire(uint256 epochId, uint256 newId) external;

    function migrate() external;



    function getTSSStatus(uint256 epochId) external view returns (TSSStatus status);

    function getPublicKeys() external view returns (bytes memory active, bytes memory retire);




}
