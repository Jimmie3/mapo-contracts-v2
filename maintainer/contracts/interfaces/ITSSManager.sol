// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import { ManagerStatus } from "../libs/Types.sol";

interface ITSSManager {

    /**
     * @dev TSS Status Enum and State Transition Documentation
     *
     * TSS Lifecycle (Single TSS Perspective):
     *
     * 1. Birth Phase (Election):
     *    UNKNOWN -> KEYGEN_PENDING -> KEYGEN_COMPLETED
     *                     ↓ (on failure)
     *               KEYGEN_FAILED (terminal state, requires new election)
     *
     * 2. Activation Phase (Taking Over):
     *    KEYGEN_COMPLETED -> MIGRATING -> MIGRATED -> ACTIVE
     *    - MIGRATING: Receiving responsibilities from previous TSS
     *    - MIGRATED: Migration complete, ready to serve
     *    - ACTIVE: Fully operational, serving as current TSS
     *
     * 3. Service Phase:
     *    ACTIVE (remains in this state until next election cycle)
     *
     * 4. Retirement Phase (Being Replaced):
     *    ACTIVE -> RETIRING -> RETIRED
     *    - RETIRING: New TSS is taking over responsibilities
     *    - RETIRED: Terminal state, TSS lifecycle complete
     *
     * Complete Lifecycle Example:
     *    Election -> UNKNOWN -> KEYGEN_PENDING -> KEYGEN_COMPLETED ->
     *    Rotation starts -> MIGRATING -> MIGRATED -> ACTIVE ->
     *    Next election cycle -> RETIRING -> RETIRED
     *
     * Special States:
     * - EMERGENCY_PAUSE: Can be triggered at any time to suspend operations
     *
     * State Transition Triggers:
     * - elect(): Initiates new TSS creation (UNKNOWN -> KEYGEN_PENDING)
     * - Off-chain keygen: Completes key generation (KEYGEN_PENDING -> KEYGEN_COMPLETED/FAILED)
     * - rotate(): Starts rotation process
     *   - New TSS: KEYGEN_COMPLETED -> MIGRATING
     *   - Old TSS: ACTIVE -> RETIRING
     * - retire(): Migration completion
     *   - New TSS: MIGRATING -> MIGRATED -> ACTIVE
     *   - Old TSS: RETIRING -> RETIRED
     */
    enum TSSStatus {
        UNKNOWN,            // Initial state, TSS not initialized
        KEYGEN_PENDING,     // TSS key generation in progress, waiting for off-chain MPC computation
        KEYGEN_COMPLETED,   // TSS key generation completed, ready to be activated
        KEYGEN_FAILED,      // TSS key generation failed, requires re-election

        MIGRATING,          // Performing emergency migration to backup TSS
        MIGRATED,           // Migration completed, original TSS has been replaced
        RETIRING,           // In retirement process, waiting for new TSS to take over
        RETIRED,            // Fully retired, no longer in use

        ACTIVE,             // Active state, currently providing service
        EMERGENCY_PAUSE     // Emergency pause, all operations suspended
    }


    function elect(uint256 electedEpochId, address[] calldata maintainers) external returns (bool);

    function rotate(uint256 currentEpochId, uint256 nextEpochId) external;

    function retire(uint256 previousEpochId, uint256 currentEpochId) external;

    function migrate() external;

    function getTSSStatus(uint256 epochId) external view returns (TSSStatus status);


}
