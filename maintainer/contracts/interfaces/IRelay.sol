// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TxInItem, TxOutItem} from "../libs/Types.sol";

interface IRelay {

    function migrate() external returns (bool completed);

    function rotate(bytes calldata _retireVault, bytes calldata _activeVault) external;

    function executeTxOut(TxOutItem memory txOutItem) external;

    function executeTxIn(TxInItem memory txInItem) external;

    function postNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionSize,
        uint256 transactionSizeWithCall,
        uint256 transactionRate
    ) external;
}
