// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps

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
}

struct GasInfo {
    address gasToken;
    uint128 estimateGas;
    uint256 transactionRate;
    uint256 transactionSize;
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



