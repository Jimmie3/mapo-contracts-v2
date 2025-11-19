// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant MAX_RATE_UNIT = 1_000_000;         // unit is 0.01 bps

enum ContractType {
    RELAY,
    GAS_SERVICE,
    VAULT_MANAGER,
    TSS_MANAGER,
    AFFILIATE,
    SWAP,
    PROTOCOL_FEE
}

enum ChainType {
    CONTRACT,       // smart contract chain supports a general-purpose smart contract virtual machine (e.g., EVM, WASM).
    NATIVE          // native chain refers to a blockchain that provides only built-in, native functionality,
                    // such as basic account operations, asset transfers, or a fixed scripting system.
                    // typical native chain includes Bitcoin (BTC), Litecoin (LTC), Dogecoin (DOGE), Zcash (ZEC), XRP Ledger (XR), etc.
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
    bytes32 vaultKey;
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
    bytes token;            // token address on the destination chain
                            // if migration, will be gas token
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



