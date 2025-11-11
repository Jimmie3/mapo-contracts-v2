// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

struct BridgeItem {
    uint256 chainAndGasLimit;
    bytes vault;
    TxType txType;
    uint256 sequence;
    bytes token;
    uint256 amount;
    bytes from;
    bytes to;
    bytes payload;
}

struct TxInItem {
    bytes32 orderId;
    BridgeItem bridgeItem;
    uint64 height;
    bytes refundAddr;
}

struct TxOutItem {
    bytes32 orderId;
    BridgeItem bridgeItem;
    uint64 height;
    uint128 gasUsed;
    address sender;
}

