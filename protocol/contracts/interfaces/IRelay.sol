// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TxOutItem, TxInItem} from "../libs/Types.sol";

interface IRelay {

    function rotate(bytes calldata retiringVault, bytes calldata activeVault) external;

    function migrate() external returns (bool completed);

    function executeTxOut(TxOutItem calldata txOutItem) external;
    function executeTxIn(TxInItem calldata txInItem) external;

    function postNetworkFee(
        uint256 chain,
        uint256 height,
        uint256 transactionSize,
        uint256 transactionSizeWithCall,
        uint256 transactionRate
    ) external;

    function getChainLastScanBlock(uint256 chain) external view returns(uint256);
}
