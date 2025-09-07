// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum ChainType {
    CONTRACT,
    UTXO,
    ACCOUNT
}

enum TxInType {
    DEPOSIT,
    SWAP
}

enum TxOutType {
    TRANSFER,
    MIGRATE
}

struct TxInItem {
    TxInType txInType;
    bytes32 orderId;
    uint128 chain;
    uint128 height;
    bytes token;
    uint256 amount;
    bytes from;
    bytes vault;
    bytes to;
    bytes data; // deposit bytes("")  swap abi.encode(tochain, playload)
}

struct TxOutItem {
    TxOutType txOutType;
    bytes32 orderId;
    uint128 height;
    uint128 chain;
    uint128 gasUsed;
    uint128 sequence;
    address sender;
    bytes to;
    bytes vault;
    bytes data;
}
// bytes token;
// uint128 amount;
// bytes to;

// struct MigrationItem {
//     bytes32 orderId;
//     bytes32 txHash;
//     uint128 height;
//     uint128 chain;
//     uint128 gasUsed;
//     uint128 sequence;
//     bytes fromVault;
//     bytes toVault;
//     address sender;
//     TokenAllowance[] allowances;
// }

// struct TokenAllowance {
//     bytes token;
//     uint256 amount;
// }
