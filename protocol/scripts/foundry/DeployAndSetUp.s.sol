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
        string memory networkName = getNetworkName();
        address authority = readConfigAddr(networkName, "Authority");
        console.log("Authority address:", authority);
        uint256 chainId = block.chainid;
        if (chainId == 212 || chainId == 22776) {
               deployRelay(networkName, authority);
               deployGasService(networkName, authority);
               deployProtocolFee(networkName, authority);
               deployRegistry(networkName, authority);
               deployVaultManager(networkName, authority);
               deployViewController(networkName, authority);
        } else {
               deployGateway(networkName, authority);
        }
    }

    function set() internal {
          uint256 chainId = block.chainid;
          if(chainId == 212 || chainId == 22776) {
               string memory networkName = getNetworkName();
               address authority = readConfigAddr(networkName, "Authority");
               console.log("Authority address:", authority);
               setUp(networkName);
          } else {
               console.log("nothing to set");
          }
    }

   function deployRelay(string memory networkName, address authority) internal returns(Relay relay) {
        string memory salt = vm.envString("GATEWAY_SALT");
        Relay impl = new Relay();
        bytes memory initData = abi.encodeWithSelector(Relay.initialize.selector, authority);
        address r = deployProxyByFactory(salt, address(impl), initData);
        relay = Relay(payable(r));

        console.log("Relay address:", r);
        console.log("Relay implementation:", address(impl));
        saveConfig(networkName, "Relay", r);

        // Record deployment for verification
        _recordDeployment(r, address(impl), "Relay", initData);

        address wToken = readConfigAddr(networkName, "wToken");
        relay.setWtoken(wToken);
        console.log("wToken address:", wToken);

   }

    function deployGateway(string memory networkName, address authority) internal returns(Gateway gateway) {
        string memory salt = vm.envString("GATEWAY_SALT");
        Gateway impl = new Gateway();
        bytes memory initData = abi.encodeWithSelector(Gateway.initialize.selector, authority);
        address g = deployProxyByFactory(salt, address(impl), initData);
        gateway = Gateway(payable(g));

        console.log("Gateway address:", g);
        console.log("Gateway implementation:", address(impl));
        saveConfig(networkName, "Gateway", g);

        // Record deployment for verification
        _recordDeployment(g, address(impl), "Gateway", initData);

        address wToken = readConfigAddr(networkName, "wToken");
        gateway.setWtoken(wToken);
        console.log("wToken address:", wToken);
   }

   function deployVaultManager(string memory networkName, address authority) internal returns(VaultManager vaultManager) {
        VaultManager impl = new VaultManager();
        bytes memory initData = abi.encodeWithSelector(VaultManager.initialize.selector, authority);
        address v = deployProxy(address(impl), initData);
        vaultManager = VaultManager(v);

        console.log("VaultManager address:", v);
        console.log("VaultManager implementation:", address(impl));
        saveConfig(networkName, "VaultManager", v);

        // Record deployment for verification
        _recordDeployment(v, address(impl), "VaultManager", initData);
   }

    function deployProtocolFee(string memory networkName, address authority) internal returns(ProtocolFee protocolFee) {
        ProtocolFee impl = new ProtocolFee();
        bytes memory initData = abi.encodeWithSelector(ProtocolFee.initialize.selector, authority);
        address p = deployProxy(address(impl), initData);
        protocolFee = ProtocolFee(payable(p));

        console.log("ProtocolFee address:", p);
        console.log("ProtocolFee implementation:", address(impl));
        saveConfig(networkName, "ProtocolFee", p);

        // Record deployment for verification
        _recordDeployment(p, address(impl), "ProtocolFee", initData);
   }


    function deployRegistry(string memory networkName, address authority) internal returns(Registry registry) {
        Registry impl = new Registry();
        bytes memory initData = abi.encodeWithSelector(Registry.initialize.selector, authority);
        address r = deployProxy(address(impl), initData);
        registry = Registry(r);

        console.log("Registry address:", r);
        console.log("Registry implementation:", address(impl));
        saveConfig(networkName, "Registry", r);

        // Record deployment for verification
        _recordDeployment(r, address(impl), "Registry", initData);
   }

   function deployGasService(string memory networkName, address authority) internal returns(GasService gasService) {
        GasService impl = new GasService();
        bytes memory initData = abi.encodeWithSelector(GasService.initialize.selector, authority);
        address g = deployProxy(address(impl), initData);
        gasService = GasService(g);

        console.log("GasService address:", g);
        console.log("GasService implementation:", address(impl));
        saveConfig(networkName, "GasService", g);

        // Record deployment for verification
        _recordDeployment(g, address(impl), "GasService", initData);
   }

    function deployViewController(string memory networkName, address authority) internal returns(ViewController viewController) {
        ViewController impl = new ViewController();
        bytes memory initData = abi.encodeWithSelector(ViewController.initialize.selector, authority);
        address v = deployProxy(address(impl), initData);
        viewController = ViewController(v);

        console.log("ViewController address:", v);
        console.log("ViewController implementation:", address(impl));
        saveConfig(networkName, "ViewController", v);

        // Record deployment for verification
        _recordDeployment(v, address(impl), "len/ViewController", initData);
   }

   function setUp(string memory networkName) internal {
        address relay_addr = readConfigAddr(networkName, "Relay");
        console.log("Relay address:", relay_addr);
        address vaultManager_addr = readConfigAddr(networkName, "VaultManager");
        console.log("VaultManager address:", vaultManager_addr);
        address protocolFee_addr = readConfigAddr(networkName, "ProtocolFee");
        console.log("ProtocolFee address:", protocolFee_addr);
        address gasService_addr = readConfigAddr(networkName, "GasService");
        console.log("GasService address:", gasService_addr);
        address registry_addr = readConfigAddr(networkName, "Registry");
        console.log("Registry address:", registry_addr);

        address TSSManager = readConfigAddr(networkName, "TSSManager");
        console.log("TSSManager address:", TSSManager);

        Relay r = Relay(payable(relay_addr));
        r.setVaultManager(vaultManager_addr);
        r.setRegistry(registry_addr);

        VaultManager v = VaultManager(vaultManager_addr);
        v.setRelay(relay_addr);
        v.setRegistry(registry_addr);

        GasService g = GasService(gasService_addr);
        g.setRegistry(registry_addr);

        address swapManager = readConfigAddr(networkName, "SwapManager");
        address affiliateManager = readConfigAddr(networkName, "AffiliateManager");
        Registry registry = Registry(registry_addr);
        registry.registerContract(ContractType.RELAY, relay_addr);
        registry.registerContract(ContractType.GAS_SERVICE, gasService_addr);
        registry.registerContract(ContractType.VAULT_MANAGER, vaultManager_addr);
        registry.registerContract(ContractType.TSS_MANAGER, TSSManager);
        registry.registerContract(ContractType.AFFILIATE, affiliateManager);
        registry.registerContract(ContractType.SWAP, swapManager);
        registry.registerContract(ContractType.PROTOCOL_FEE, protocolFee_addr);

        address viewController_addr = readConfigAddr(networkName, "ViewController");
        ViewController vc = ViewController(viewController_addr);
        console.log("ViewController address:", viewController_addr);
        vc.setRegistry(registry_addr);
   }

   function upgrade(string memory c) internal {
     string memory networkName = getNetworkName();
     if(keccak256(bytes(c)) == keccak256(bytes("Relay"))) {
          address relay_addr = readConfigAddr(networkName, "Relay");
          Relay r = Relay(payable(relay_addr));
          Relay impl = new Relay();
          r.upgradeToAndCall(address(impl), bytes(""));
     } else if(keccak256(bytes(c)) == keccak256(bytes("VaultManager"))) {
          address vaultManager_addr = readConfigAddr(networkName, "VaultManager");
          VaultManager v = VaultManager(vaultManager_addr);
          VaultManager impl = new VaultManager();
          v.upgradeToAndCall(address(impl), bytes(""));
     } else if(keccak256(bytes(c)) == keccak256(bytes("GasService"))) {
          address gasService_addr = readConfigAddr(networkName, "GasService");
          GasService g = GasService(gasService_addr);
          GasService impl = new GasService();
          g.upgradeToAndCall(address(impl), bytes(""));
     } else if(keccak256(bytes(c)) == keccak256(bytes("Registry"))) {
          address registry_addr = readConfigAddr(networkName, "Registry");
          Registry r = Registry(registry_addr);
          Registry impl = new Registry();
          r.upgradeToAndCall(address(impl), bytes(""));
     } else if(keccak256(bytes(c)) == keccak256(bytes("ProtocolFee"))) {
          address protocolFee_addr = readConfigAddr(networkName, "ProtocolFee");
          ProtocolFee p = ProtocolFee(payable(protocolFee_addr));
          ProtocolFee impl = new ProtocolFee();
          p.upgradeToAndCall(address(impl), bytes(""));
     } else if(keccak256(bytes(c)) == keccak256(bytes("Gateway"))) {
          address gateway_addr = readConfigAddr(networkName, "Gateway");
          Gateway g = Gateway(payable(gateway_addr));
          Gateway impl = new Gateway();
          g.upgradeToAndCall(address(impl), bytes(""));
     } else if(keccak256(bytes(c)) == keccak256(bytes("ViewController"))) {
          address viewController_addr = readConfigAddr(networkName, "ViewController");
          ViewController v = ViewController(viewController_addr);
          ViewController impl = new ViewController();
          v.upgradeToAndCall(address(impl), bytes(""));
     } {
          revert("unknow contract");
     }
   }

}
