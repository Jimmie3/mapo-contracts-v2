// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ChainType, GasInfo} from "../libs/Types.sol";
import {IGasService} from "../interfaces/IGasService.sol";
import {IVaultManager} from "../interfaces/IVaultManager.sol";
import {IRelay} from "../interfaces/IRelay.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IPeriphery} from "../interfaces/IPeriphery.sol";
import {ITSSManager} from "../interfaces/ITSSManager.sol";
import {BaseImplementation} from "@mapprotocol/common-contracts/contracts/base/BaseImplementation.sol";

contract ViewController is BaseImplementation {
    uint256 public immutable selfChainId = block.chainid;


    IPeriphery public periphery;

    event SetPeriphery(address _periphery);

    function initialize(address _defaultAdmin) public initializer {
        __BaseImplementation_init(_defaultAdmin);
    }

    function setPeriphery(address _periphery) external restricted {
        require(_periphery != address(0));
        periphery = IPeriphery(_periphery);
        emit SetPeriphery(_periphery);
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
        IRegistry r = _getRegistery();
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
        IRegistry r = _getRegistery();
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
        uint256 balance;
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
        IVaultManager vm = _getVaultManager();
        IRegistry r = _getRegistery();
        vaultView.pubKey = pubkey;
        vaultView.chains = r.getChains();

        uint256 len = vaultView.chains.length;
        vaultView.routerTokens = new RouterTokens[](len);
        vaultView.members = _getMembers(pubkey);
        for (uint i = 0; i < len; i++) {
            uint256 chain = vaultView.chains[i];
            vaultView.routerTokens[i].chain = chain;
            if(r.getChainType(chain) == ChainType.CONTRACT) {
                vaultView.routerTokens[i].router = r.getChainRouters(chain);
            } else {
                vaultView.routerTokens[i].router = pubkey;
            }
            bytes[] memory tokens = r.getChainTokens(chain);
            uint256 tokenLen = tokens.length;
            vaultView.routerTokens[i].coins = new Token[](tokenLen);
            for (uint j = 0; j < tokenLen; j++) {
                vaultView.routerTokens[i].coins[j].token = tokens[i];
                vaultView.routerTokens[i].coins[j].decimals = r.getTokenDecimals(chain, tokens[i]);
                address relayToken = r.getRelayChainToken(chain, tokens[i]);
                (uint256 balance, uint256 pendingOut) = vm.getVaultTokenBalance(pubkey, chain, relayToken);
                vaultView.routerTokens[i].coins[j].balance = _adjustDecimals(balance, vaultView.routerTokens[i].coins[j].decimals);
                vaultView.routerTokens[i].coins[j].pendingOut = _adjustDecimals(pendingOut, vaultView.routerTokens[i].coins[j].decimals);
            }
        }
    }

    function _getMembers(bytes calldata pubkey) internal view returns(address[] memory) {
        return _getTSSManager().getMembers(pubkey);
    }

    function _adjustDecimals(uint256 amount, uint256 decimals) internal pure returns(uint256) {
        return amount * 10 ** decimals / (10 ** 18);
    }

    function _getRelay() internal view returns (IRelay relay) {
        relay = IRelay(periphery.getAddress(0));
    }

    function _getRegistery() internal view returns (IRegistry registery) {
        registery = IRegistry(periphery.getAddress(3));
    }

    function _getGasService() internal view returns (IGasService gasService) {
        gasService = IGasService(periphery.getAddress(1));
    }

    function _getVaultManager() internal view returns (IVaultManager vaultManager) {
        vaultManager = IVaultManager(periphery.getAddress(2));
    }

    function _getTSSManager() internal view returns (ITSSManager TSSManager) {
        TSSManager = ITSSManager(periphery.getAddress(4));
    }
}
