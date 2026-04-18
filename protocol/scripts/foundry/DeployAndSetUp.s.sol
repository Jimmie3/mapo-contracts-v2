// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployAndSetUp
 * @notice Deploy protocol contracts with optional auto-verification
 *
 * @dev Deploy Commands:
 *
 * MAPO Mainnet (Blockscout - deploy first, then verify separately):
 *   # Step 1: Deploy
 *   forge script scripts/foundry/DeployAndSetUp.s.sol:DeployAndSetUp \
 *     --rpc-url Mapo --broadcast
 *
 *   # Step 2: Verify each contract (run after deployment)
 *   forge verify-contract <ADDRESS> <CONTRACT> \
 *     --verifier blockscout \
 *     --verifier-url https://explorer-api.chainservice.io/api
 *
 * Ethereum/BSC/Base/Arb (Etherscan - supports --verify flag):
 *   forge script scripts/foundry/DeployAndSetUp.s.sol:DeployAndSetUp \
 *     --rpc-url Eth --broadcast --verify
 *
 * Environment Variables:
 *   PRIVATE_KEY          - Mainnet deployer private key
 *   TESTNET_PRIVATE_KEY  - Testnet deployer private key
 *   NETWORK_ENV          - Required: test/prod/main
 *   GATEWAY_SALT         - Salt for CREATE2 deployment
 *   ETHERSCAN_API_KEY    - Etherscan API key
 */

import {BaseScript, console} from "./Base.s.sol";
import {Relay} from "../../contracts/Relay.sol";
import {VaultManager} from "../../contracts/VaultManager.sol";
import {ProtocolFee} from "../../contracts/ProtocolFee.sol";
import {Gateway} from "../../contracts/Gateway.sol";
import {GasService} from "../../contracts/GasService.sol";
import {Registry} from "../../contracts/Registry.sol";
import {ViewController} from "../../contracts/len/ViewController.sol";
import {IRegistry, ContractType} from "../../contracts/interfaces/IRegistry.sol";

contract DeployAndSetUp is BaseScript {

    function run() public virtual broadcast {
          deploy();
          set();

          // Print verification commands after deployment
          printVerificationCommands();
    }

    function deploy() internal {
        address authority = readDeployment("Authority");
        console.log("Authority address:", authority);
        uint256 chainId = block.chainid;
        if (chainId == 212 || chainId == 22776) {
               deployRelay(authority);
               deployGasService(authority);
               deployProtocolFee(authority);
               deployRegistry(authority);
               deployVaultManager(authority);
               deployViewController(authority);
        } else {
               deployGateway(authority);
        }
    }

    function set() internal {
          uint256 chainId = block.chainid;
          if(chainId == 212 || chainId == 22776) {
               setUp();
          } else {
               console.log("nothing to set");
          }
    }

   function deployRelay(address authority) internal returns(Relay relay) {
        string memory salt = vm.envString("GATEWAY_SALT");
        bytes memory initData = abi.encodeWithSelector(Relay.initialize.selector, authority);
        (address r, address impl) = deployProxyByFactory(salt, type(Relay).creationCode, initData);
        relay = Relay(payable(r));

        console.log("Relay address:", r);
        console.log("Relay implementation:", impl);
        saveDeployment("Relay", r);

        _recordDeployment(r, impl, "Relay", initData);

        address wToken = readDeployment("wToken");
        relay.setWtoken(wToken);
        console.log("wToken address:", wToken);
   }

    function deployGateway(address authority) internal returns(Gateway gateway) {
        string memory salt = vm.envString("GATEWAY_SALT");
        bytes memory initData = abi.encodeWithSelector(Gateway.initialize.selector, authority);
        (address g, address impl) = deployProxyByFactory(salt, type(Gateway).creationCode, initData);
        gateway = Gateway(payable(g));

        console.log("Gateway address:", g);
        console.log("Gateway implementation:", impl);
        saveDeployment("Gateway", g);

        _recordDeployment(g, impl, "Gateway", initData);

        address wToken = readDeployment("wToken");
        gateway.setWtoken(wToken);
        console.log("wToken address:", wToken);
   }

   function deployVaultManager(address authority) internal returns(VaultManager vaultManager) {
        bytes memory initData = abi.encodeWithSelector(VaultManager.initialize.selector, authority);
        (address v, address impl) = deployProxy(type(VaultManager).creationCode, initData);
        vaultManager = VaultManager(v);

        console.log("VaultManager address:", v);
        console.log("VaultManager implementation:", impl);
        saveDeployment("VaultManager", v);

        _recordDeployment(v, impl, "VaultManager", initData);
   }

    function deployProtocolFee(address authority) internal returns(ProtocolFee protocolFee) {
        bytes memory initData = abi.encodeWithSelector(ProtocolFee.initialize.selector, authority);
        (address p, address impl) = deployProxy(type(ProtocolFee).creationCode, initData);
        protocolFee = ProtocolFee(payable(p));

        console.log("ProtocolFee address:", p);
        console.log("ProtocolFee implementation:", impl);
        saveDeployment("ProtocolFee", p);

        _recordDeployment(p, impl, "ProtocolFee", initData);
   }

    function deployRegistry(address authority) internal returns(Registry registry) {
        bytes memory initData = abi.encodeWithSelector(Registry.initialize.selector, authority);
        (address r, address impl) = deployProxy(type(Registry).creationCode, initData);
        registry = Registry(r);

        console.log("Registry address:", r);
        console.log("Registry implementation:", impl);
        saveDeployment("Registry", r);

        _recordDeployment(r, impl, "Registry", initData);
   }

   function deployGasService(address authority) internal returns(GasService gasService) {
        bytes memory initData = abi.encodeWithSelector(GasService.initialize.selector, authority);
        (address g, address impl) = deployProxy(type(GasService).creationCode, initData);
        gasService = GasService(g);

        console.log("GasService address:", g);
        console.log("GasService implementation:", impl);
        saveDeployment("GasService", g);

        _recordDeployment(g, impl, "GasService", initData);
   }

    function deployViewController(address authority) internal returns(ViewController viewController) {
        bytes memory initData = abi.encodeWithSelector(ViewController.initialize.selector, authority);
        (address v, address impl) = deployProxy(type(ViewController).creationCode, initData);
        viewController = ViewController(v);

        console.log("ViewController address:", v);
        console.log("ViewController implementation:", impl);
        saveDeployment("ViewController", v);

        _recordDeployment(v, impl, "len/ViewController", initData);
   }

   function setUp() internal {
        address relay_addr = readDeployment("Relay");
        console.log("Relay address:", relay_addr);
        address vaultManager_addr = readDeployment("VaultManager");
        console.log("VaultManager address:", vaultManager_addr);
        address protocolFee_addr = readDeployment("ProtocolFee");
        console.log("ProtocolFee address:", protocolFee_addr);
        address gasService_addr = readDeployment("GasService");
        console.log("GasService address:", gasService_addr);
        address registry_addr = readDeployment("Registry");
        console.log("Registry address:", registry_addr);

        address TSSManager = readDeployment("TSSManager");
        console.log("TSSManager address:", TSSManager);

        Relay r = Relay(payable(relay_addr));
        r.setVaultManager(vaultManager_addr);
        r.setRegistry(registry_addr);

        VaultManager v = VaultManager(vaultManager_addr);
        v.setRelay(relay_addr);
        v.setRegistry(registry_addr);

        GasService g = GasService(gasService_addr);
        g.setRegistry(registry_addr);

        address swapManager = readDeployment("SwapManager");
        address affiliateManager = readDeployment("AffiliateManager");
        Registry registry = Registry(registry_addr);
        registry.registerContract(ContractType.RELAY, relay_addr);
        registry.registerContract(ContractType.GAS_SERVICE, gasService_addr);
        registry.registerContract(ContractType.VAULT_MANAGER, vaultManager_addr);
        registry.registerContract(ContractType.TSS_MANAGER, TSSManager);
        registry.registerContract(ContractType.AFFILIATE, affiliateManager);
        registry.registerContract(ContractType.SWAP, swapManager);
        registry.registerContract(ContractType.PROTOCOL_FEE, protocolFee_addr);

        address viewController_addr = readDeployment("ViewController");
        ViewController vc = ViewController(viewController_addr);
        console.log("ViewController address:", viewController_addr);
        vc.setRegistry(registry_addr);
   }

   function upgradeContract(string memory c) public broadcast {
        upgrade(c);
   }

   function upgrade(string memory c) internal {
     if(keccak256(bytes(c)) == keccak256(bytes("Relay"))) {
          address relay_addr = readDeployment("Relay");
          deployAndUpgrade(relay_addr, type(Relay).creationCode);
     } else if(keccak256(bytes(c)) == keccak256(bytes("VaultManager"))) {
          address vaultManager_addr = readDeployment("VaultManager");
          deployAndUpgrade(vaultManager_addr, type(VaultManager).creationCode);
     } else if(keccak256(bytes(c)) == keccak256(bytes("GasService"))) {
          address gasService_addr = readDeployment("GasService");
          deployAndUpgrade(gasService_addr, type(GasService).creationCode);
     } else if(keccak256(bytes(c)) == keccak256(bytes("Registry"))) {
          address registry_addr = readDeployment("Registry");
          deployAndUpgrade(registry_addr, type(Registry).creationCode);
     } else if(keccak256(bytes(c)) == keccak256(bytes("ProtocolFee"))) {
          address protocolFee_addr = readDeployment("ProtocolFee");
          deployAndUpgrade(protocolFee_addr, type(ProtocolFee).creationCode);
     } else if(keccak256(bytes(c)) == keccak256(bytes("Gateway"))) {
          address gateway_addr = readDeployment("Gateway");
          deployAndUpgrade(gateway_addr, type(Gateway).creationCode);
     } else if(keccak256(bytes(c)) == keccak256(bytes("ViewController"))) {
          address viewController_addr = readDeployment("ViewController");
          deployAndUpgrade(viewController_addr, type(ViewController).creationCode);
     } else {
          revert("unknown contract");
     }
   }

}
