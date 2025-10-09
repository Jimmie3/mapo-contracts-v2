// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainType} from "../libs/Types.sol";

interface IRegistry {
    function getTokenAddressById(uint96 id) external view returns (address token);
    // Get token address on target chain
    function getToChainToken(address _token, uint256 _toChain) external view returns (bytes memory _toChainToken);

    // Get token amount on target chain
    function getToChainAmount(address _token, uint256 _amount, uint256 _toChain) external view returns (uint256);

    // Get token and vault token address on relay chain
    function getRelayChainToken(uint256 _fromChain, bytes memory _fromToken) external view returns (address);

    // Get token amount on relay chain
    function getRelayChainAmount(bytes memory _fromToken, uint256 _fromChain, uint256 _amount)
        external
        view
        returns (uint256);

    function getTargetToken(uint256 _fromChain, uint256 _toChain, bytes memory _fromToken)
        external
        view
        returns (bytes memory toToken, uint8 decimals, uint256 vaultBalance);

    function getTargetAmount(uint256 _fromChain, uint256 _toChain, bytes memory _fromToken, uint256 _amount)
        external
        view
        returns (uint256 toAmount);

    function getVaultToken(address _token) external view returns (address);

    function getBaseFeeReceiver() external view returns (address);

    // get from chain fee
    function getTransferInFee(bytes memory _caller, address _token, uint256 _amount, uint256 _fromChain)
        external
        view
        returns (uint256 bridgeFee);

    // get to chain fee
    function getTransferOutFee(
        bytes memory _caller,
        address _token,
        uint256 _amount,
        uint256 _fromChain,
        uint256 _toChain,
        bool _withSwap
    ) external view returns (uint256 securityFee, uint256 vaultFee);

    // get token transfer fee, the larger one of transfer in or transfer out fee
    function getTransferFee(
        bytes memory _caller,
        address _token,
        uint256 _amount,
        uint256 _fromChain,
        uint256 _toChain,
        bool _withSwap
    ) external view returns (uint256 totalFee, uint256 baseFee, uint256 bridgeFee);

    function getBridgeFeeInfo(
        bytes memory _caller,
        bytes memory _fromToken,
        address _bridgeToken,
        uint256 _fromChain,
        uint256 _fromAmount,
        uint256 _toChain,
        bool _withSwap
    ) external view returns (uint256 fromChainFee, uint256 toChainVault);

    function getChains() external view returns (uint256[] memory);

    function getChainTokens(uint256 chain) external view returns (bytes[] memory);

    function getChainRouters(uint256 chain) external view returns (bytes memory router);

    function getTokenDecimals(uint256 chain, bytes calldata token) external view returns (uint256);

    function getChainName(uint256 chain) external view returns (string memory);

    function getChainByName(string memory name) external view returns (uint256);

    function getTokenNickname(uint256 chain, bytes memory token) external view returns (string memory);

    function getChainType(uint256 chain) external view returns (ChainType);

    function getChainGasToken(uint256 chain) external view returns (address);

    function getTokenAddressByNickname(uint256 chain, string memory nickname) external view returns (bytes memory);

    // function getVaultBalanceByToken(uint256 chain, bytes memory token) external view returns (uint256 vaultBalance);
}
