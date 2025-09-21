// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ChainType} from "./libs/Types.sol";
import {IPeriphery} from "./interfaces/IPeriphery.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

import {IRegistry} from "./interfaces/IRegistry.sol";
import {ISwap} from "./interfaces/ISwap.sol";
import {IGasService} from "./interfaces/IGasService.sol";

contract Periphery is BaseImplementation, IPeriphery {
    bytes32 private constant RELAY_ADDRESS_KEY = keccak256("address.relay");
    bytes32 private constant GAS_SERVICE_ADDRESS_KEY = keccak256("address.gasservice");
    bytes32 private constant REGISTRY_ADDRESS_KEY = keccak256("address.register");
    bytes32 private constant VAULT_MANAGER_ADDRESS_KEY = keccak256("address.vaultmanager");
    bytes32 private constant TSS_MANAGER_ADDRESS_KEY = keccak256("address.tssmanager");

    bytes32 private constant AFFILIATE_ADDRESS_KEY = keccak256("address.affiliate");
    bytes32 private constant SWAP_ADDRESS_KEY = keccak256("address.swap");

    address public relay;
    address public gasService;
    address public tokenRegistry;
    address public vaultManager;
    address public tssManager;

    address public affiliateFeeManager;
    address public swap;

    mapping(bytes32 => address) public addresses;

    event SetRelay(address _relay);
    event SetGasService(address _gasService);
    event SetVaultManager(address vaultManager);
    event SetTSSManager(address _tssManager);
    event SetTokenRegister(address _tokenRegister);

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setRelay(address _relay) external restricted {
        require(_relay != address(0));
        relay = _relay;
        emit SetRelay(_relay);
    }

    function setGasService(address _gasService) external restricted {
        require(_gasService != address(0));
        gasService = _gasService;
        emit SetGasService(_gasService);
    }

    function setVaultManager(address _vaultManager) external restricted {
        require(_vaultManager != address(0));
        vaultManager = _vaultManager;
        emit SetVaultManager(_vaultManager);
    }

    function setTSSManager(address _tssManager) external restricted {
        require(_tssManager != address(0));
        tssManager = _tssManager;
        emit SetTSSManager(_tssManager);
    }

    function setTokenRegister(address _tokenRegister) external restricted {
        require(_tokenRegister != address(0));
        tokenRegistry = _tokenRegister;
        emit SetTokenRegister(_tokenRegister);
    }

    function getAddress(uint256 t) external view returns (address addr) {
        if (t == 0) {
            addr = relay;
        } else if (t == 1) {
            addr = gasService;
        } else if (t == 2) {
            addr = vaultManager;
        } else if (t == 3) {
            addr = tokenRegistry;
        } else {
            addr = tssManager;
        }
    }

    function getChainType(uint256 _chain) external view returns (ChainType) {
        return IRegistry(tokenRegistry).getChainType(_chain);
    }

    function getChainGasToken(uint256 _chain) external view returns (address) {
        return IRegistry(tokenRegistry).getChainGasToken(_chain);
    }

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256) {
        return ISwap(swap).getAmountOut(tokenIn, tokenOut, amountIn);
    }

    function getNetworkFeeInfoWithToken(address token, uint256 chain, bool withCall)
    external
    view
    override
    returns (uint256 relayGasFee, uint256 transactionRate, uint256 transactionSize)
    {
        uint256 networkFee;
        (networkFee, transactionRate, transactionSize) = IGasService(gasService).getNetworkFeeInfo(chain, withCall);

        IRegistry r = IRegistry(tokenRegistry);
        address relayGasToken = r.getChainGasToken(chain);
        bytes memory gasToken = r.getToChainToken(relayGasToken, chain);
        uint256 relayNetworkFee = r.getRelayChainAmount(gasToken, chain, networkFee);

        if (relayGasToken == token) {
            relayGasFee = relayNetworkFee;
        } else {
            relayGasFee = ISwap(swap).getAmountOut(relayGasToken, token, relayNetworkFee);
        }
    }

    function isRelay(address _sender) external view returns (bool) {
        return (_sender == relay);
    }

    function isTssManager(address _sender) external view returns (bool) {
        return (_sender == tssManager);
    }
}
