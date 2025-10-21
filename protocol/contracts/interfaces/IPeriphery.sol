// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainType, GasInfo} from "../libs/Types.sol";

/**
 * @title IPeriphery
 * @dev Central registry interface for accessing protocol components and utilities
 * Provides unified access point for various protocol addresses and helper functions
 */
interface IPeriphery {
    /**
     * @dev Get protocol component address by type
     * @param t Component type identifier:
     *        0: Relay contract address
     *        1: GasService contract address
     *        2: VaultManager contract address
     *        3: TokenRegistry contract address
     *        4+: TSSManager contract address
     * @return addr Address of the requested component
     */
    function getAddress(uint256 t) external view returns (address addr);


    function getSwap() external view returns (address);

    function getAffiliateManager() external view returns (address);

    function getProtocolFee(address token, uint256 amount) external view returns (address, uint256);

    /**
     * @dev Get the type of blockchain for a given chain ID
     * @param chain Chain ID to query
     * @return ChainType enum value (UTXO, CONTRACT, etc.)
     */
    function getChainType(uint256 chain) external view returns (ChainType);

    /**
     * @dev Get the native gas token address for a specific chain
     * @param _chain Chain ID to query
     * @return Address of the gas token on the relay chain
     */
    function getChainGasToken(uint256 _chain) external view returns (address);

    /**
     * @dev Calculate output amount for a token swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return Expected output amount after swap
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);

    /**
     * @dev Get network fee information with conversion to specified token
     * @param token Token address to denominate the fee in
     * @param chain Target chain ID
     * @param withCall Whether the transaction includes a contract call
     * @return Total gas fee in the specified token, include txRate(gasPrice) and txSize(gasLimit)
     */
    function getNetworkFeeInfoWithToken(address token, uint256 chain, bool withCall) external view returns (GasInfo memory);

    // Get network fee with the chain base token
    // for non-contract chain, it will be the gas token
    function getNetworkFeeInfo(uint256 chain, bool withCall) external view returns (GasInfo memory);

    /**
     * @dev Check if an address is the Relay contract
     * @param sender Address to verify
     * @return True if sender is the Relay contract
     */
    function isRelay(address sender) external view returns (bool);

    /**
     * @dev Check if an address is the TSSManager contract
     * @param sender Address to verify
     * @return True if sender is the TSSManager contract
     */
    function isTssManager(address sender) external view returns (bool);
}
