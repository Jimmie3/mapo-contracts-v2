// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum ChainType {
    CONTRACT,
    NON_CONTRACT
}

enum TxType {
    DEPOSIT,
    TRANSFER,
    MIGRATE,
    REFUND, //
    MESSAGE // todo
}

struct TxItem {
    bytes32 orderId;
    uint256 chain;
    ChainType chainType;
    address token;
    uint256 amount;
    address to;
}

struct GasInfo {
    address gasToken;
    uint256 estimateGas;
    uint256 transactionRate;
    uint256 transactionSize;
    bytes vault;
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
    uint128 gasUsed;        // native token used
    address sender;
}



