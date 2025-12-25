// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainType, GasInfo, ContractType} from "../libs/Types.sol";

interface IRegistry {

    function getContractAddress(ContractType _contractType) external view  returns(address);

    function getTokenAddressById(uint96 id) external view returns (address token);

    // Get token address on target chain
    function getToChainToken(address _token, uint256 _toChain) external view returns (bytes memory _toChainToken);

    function getTokenInfo(address _relayToken, uint256 _fromChain)
    external
    view
    returns (bytes memory token, uint8 decimals, bool mintable);

    function getTargetToken(uint256 _fromChain, uint256 _toChain, bytes memory _fromToken)
    external
    view
    returns (bytes memory toToken, uint8 decimals);

    function getRelayChainGasAmount(uint256 chain, uint256 gasAmount) external view returns (uint256 relayGasAmount);

    // Get token and vault token address on relay chain
    function getRelayChainToken(uint256 _fromChain, bytes memory _fromToken) external view returns (address);

    // Get token amount on target chain
    function getToChainAmount(address _token, uint256 _amount, uint256 _toChain) external view returns (uint256);

    // Get token amount on relay chain
    function getRelayChainAmount(bytes memory _fromToken, uint256 _fromChain, uint256 _amount)
        external
        view
        returns (uint256);

    function getTargetAmount(uint256 _fromChain, uint256 _toChain, bytes memory _fromToken, uint256 _amount)
        external
        view
        returns (uint256 toAmount);

    function getChains() external view returns (uint256[] memory);

    function getChainTokens(uint256 chain) external view returns (bytes[] memory);

    function getChainRouters(uint256 chain) external view returns (bytes memory router);

    function getTokenDecimals(uint256 chain, bytes calldata token) external view returns (uint256);

    function getChainName(uint256 chain) external view returns (string memory);

    function getChainByName(string memory name) external view returns (uint256);

    function getTokenNickname(uint256 chain, bytes memory token) external view returns (string memory);

    function getChainType(uint256 chain) external view returns (ChainType);

    function getChainGasToken(uint256 chain) external view returns (address);

    function getChainBaseToken(uint256 chain) external view returns (address);

    function isRegistered(uint256 chain) external view returns (bool);

    function getTokenAddressByNickname(uint256 chain, string memory nickname) external view returns (bytes memory);

    function getProtocolFee(address token, uint256 amount) external view returns (address, uint256);

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);

    function getNetworkFeeInfoWithToken(address token, uint256 chain, bool withCall)
    external
    view
    returns (GasInfo memory);

    function getNetworkFeeInfo(uint256 chain, bool withCall)
    external
    view
    returns (GasInfo memory);
    
    function getMigrateGasFee(uint256 chain, address feePaidToken, uint256 estimateGas) external view returns (uint256 amount);
}
