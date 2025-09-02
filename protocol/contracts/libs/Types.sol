// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

struct TransferItem {
    uint256 chain;
    bytes32 orderId;
    address token;
    uint256 amount;
    uint256 transactionRate;
    uint256 transactionSize;
    bytes memory to;
    bytes memory vault;
    bytes memory data;
}

struct TxInItem {
    TxInType txInType;
    bytes32 orderId;
    uint128 chain;
    uint128 height;
    uint64 toChain;
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
