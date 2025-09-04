// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum ChainType {
    CONTRACT,
    UTXO,
    ACCOUNT
}

enum TxType {
    DEPOSIT,
    TRANSFER,
    MIGRATE,
    REFUND, //
    MESSAGE // todo

}

struct TxItem {
    uint256 fromChain;
    uint256 toChain;
    bytes32 orderId;
    address token;
    uint256 amount;
    uint256 transactionRate;
    uint256 transactionSize;
    bytes vault;
    bytes from;
    bytes to;
    bytes payload;
}

struct TxInItem {
    TxType txInType;
    bytes32 orderId;
    uint128 chain;
    uint128 height;
    uint64 toChain;
    bytes token;
    uint256 amount;
    bytes from;
    bytes vault;
    bytes to;
    bytes data;
}

struct TxOutItem {
    TxType txOutType;
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
