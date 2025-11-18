// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ChainType, GasInfo} from "../libs/Types.sol";
import {IGasService} from "../interfaces/IGasService.sol";
import {IVaultManager} from "../interfaces/IVaultManager.sol";
import {IRelay} from "../interfaces/IRelay.sol";
import {IRegistry, ContractAddress, ChainType, GasInfo} from "../interfaces/IRegistry.sol";
import {ITSSManager} from "../interfaces/ITSSManager.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract ViewController is BaseImplementation {
    uint256 public immutable selfChainId = block.chainid;

    IRegistry public registry;

    event SetRegistry(address _registry);

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setRegistry(address _registry) external restricted {
        require(_registry != address(0));
        registry = IRegistry(_registry);
        emit SetRegistry(_registry);
    }

    function getLastTxOutHeight() external view returns (uint256) {
        IRelay relay = _getRelay();
        return relay.getChainLastScanBlock(selfChainId);
    }

    function getLastTxInHeight(uint256 chain) external view returns (uint256) {
        IRelay relay = _getRelay();
        return relay.getChainLastScanBlock(chain);
    }

    struct VaultRouter {
        uint256 chain;
        bytes router;
    }
    struct VaultInfo {
        bytes pubkey;
        VaultRouter[] routers;
    }
    function getPublickeys() external view returns(VaultInfo[] memory infos) {
        IVaultManager vm = _getVaultManager();
        IRegistry r = registry;
        uint256[] memory chains = r.getChains();
        bytes memory active = vm.getActiveVault();
        bytes memory retiring = vm.getRetiringVault();
        if(retiring.length > 0) {
            infos = new VaultInfo[](2);
            infos[0] = _getVaultInfo(r, chains, active);
            infos[1] = _getVaultInfo(r, chains, retiring);
        } else {
            infos = new VaultInfo[](1);
            infos[0] = _getVaultInfo(r, chains, active);
        }
    }

    function _getVaultInfo(IRegistry r, uint256[] memory chains, bytes memory pubkey) internal view  returns (VaultInfo memory info) {
        uint256 len = chains.length;
        info.pubkey = pubkey;
        info.routers = new VaultRouter[](len);
        for (uint i = 0; i < len; i++) {
            uint256 chain = chains[i];
            info.routers[i].chain = chain;
            if(r.getChainType(chain) == ChainType.CONTRACT) {
                info.routers[i].router = r.getChainRouters(chain);
            } else {
                info.routers[i].router = pubkey;
            }
        }
    }

    struct InboundAddress {
        uint256 chain;
        bytes pubkey;
        bytes router;
        uint256 gasRate;
        uint256 txSize;
        uint256 txSizeWithCall;
    }

    function getInboundAddress() external view returns (InboundAddress[] memory inbounds) {
        IVaultManager vm = _getVaultManager();
        IRegistry r = registry;
        IGasService g = _getGasService();
        uint256[] memory chains = r.getChains();
        bytes memory active = vm.getActiveVault();
        uint256 len = chains.length;
        inbounds = new InboundAddress[](len);
        for (uint i = 0; i < len; i++) {
            uint256 chain = chains[i];
            inbounds[i].pubkey = active;
            inbounds[i].chain = chain;
            if(r.getChainType(chain) == ChainType.CONTRACT) {
                inbounds[i].router = r.getChainRouters(chain);
            } else {
                inbounds[i].router = active;
            }
            (inbounds[i].gasRate, inbounds[i].txSize, inbounds[i].txSizeWithCall) = g.getNetworkFeeInfo(chain);
        }
    }

    struct Token {
        bytes token;
        int256 balance;
        uint256 pendingOut;
        uint256 decimals;
    }
    struct RouterTokens {
        uint256 chain;
        bytes router;
        Token[] coins;
    }
    struct VaultView {
        bytes pubKey;
        address[] members;
        uint256[] chains;
        RouterTokens[] routerTokens;
    }

    function getVault(bytes calldata pubkey) external view returns (VaultView memory vaultView) {

        IRegistry r = registry;
        vaultView.pubKey = pubkey;

        IVaultManager vm = _getVaultManager();
        vaultView.chains = vm.getBridgeChains();
        vaultView.members = _getMembers(pubkey);
        address[] memory tokens = vm.getBridgeTokens();

        uint256 tokenLen = tokens.length;
        uint256 len = vaultView.chains.length;
        vaultView.routerTokens = new RouterTokens[](len);

        for (uint i = 0; i < len; i++) {
            uint256 chain = vaultView.chains[i];
            vaultView.routerTokens[i].chain = chain;
            if(r.getChainType(chain) == ChainType.CONTRACT) {
                vaultView.routerTokens[i].router = r.getChainRouters(chain);
            } else {
                vaultView.routerTokens[i].router = pubkey;
            }
            
            vaultView.routerTokens[i].coins = new Token[](tokenLen);
            for (uint j = 0; j < tokenLen; j++) {
                bytes memory toChainToken = r.getToChainToken(tokens[j], chain);
                vaultView.routerTokens[i].coins[j].token = toChainToken;
                if(chain == selfChainId) {
                    vaultView.routerTokens[i].coins[j].decimals = 18;
                    (vaultView.routerTokens[i].coins[j].balance, vaultView.routerTokens[i].coins[j].pendingOut) = vm.getVaultTokenBalance(pubkey, chain, tokens[j]);
                } else {
                    if(toChainToken.length > 0) {
                        vaultView.routerTokens[i].coins[j].decimals = r.getTokenDecimals(chain, toChainToken);
                        (int256 balance, uint256 pendingOut) = vm.getVaultTokenBalance(pubkey, chain, tokens[j]);
                        vaultView.routerTokens[i].coins[j].balance = _adjustDecimalsInt256(balance, vaultView.routerTokens[i].coins[j].decimals);
                        vaultView.routerTokens[i].coins[j].pendingOut = _adjustDecimals(pendingOut, vaultView.routerTokens[i].coins[j].decimals);
                    }
                }
            }
        }
    }

    function _getMembers(bytes calldata pubkey) internal view returns(address[] memory) {
        return _getTSSManager().getMembers(pubkey);
    }

    function _adjustDecimals(uint256 amount, uint256 decimals) internal pure returns(uint256) {
        return amount * 10 ** decimals / (10 ** 18);
    }

    function _adjustDecimalsInt256(int256 amount, uint256 decimals) internal pure returns(int256) {
        return amount * int256(10 ** decimals) / (10 ** 18);
    }

    function _getRelay() internal view returns (IRelay relay) {
        relay = IRelay(registry.getContractAddress(ContractAddress.RELAY));
    }

    function _getGasService() internal view returns (IGasService gasService) {
        gasService = IGasService(registry.getContractAddress(ContractAddress.GAS_SERVICE));
    }

    function _getVaultManager() internal view returns (IVaultManager vaultManager) {
        vaultManager = IVaultManager(registry.getContractAddress(ContractAddress.VAULT_MANAGER));
    }

    function _getTSSManager() internal view returns (ITSSManager TSSManager) {
        TSSManager = ITSSManager(registry.getContractAddress(ContractAddress.TSS_MANAGER));
    }
}
