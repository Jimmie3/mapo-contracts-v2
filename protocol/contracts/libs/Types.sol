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
        bytes32 orderId;
        address vaultAddress;
        uint256 chain;
        address token;
        uint256 amount;
        address to;
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
    uint128 height;
    bytes refundAddr;
}

struct TxOutItem {
    bytes32 orderId;
    BridgeItem bridgeItem;
    uint128 height;
    uint128 gasUsed;
    address sender;
}



