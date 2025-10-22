// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseScript, console} from "./Base.s.sol";
import {Relay} from "../../contracts/Relay.sol";
import {VaultManager} from "../../contracts/VaultManager.sol";
import {ProtocolFee} from "../../contracts/ProtocolFee.sol";
import {Periphery} from "../../contracts/Periphery.sol";
import {Gateway} from "../../contracts/Gateway.sol";
import {GasService} from "../../contracts/GasService.sol";
import {Registry} from "../../contracts/Registry.sol";
import {ViewController} from "../../contracts/len/ViewController.sol";

contract DeployAndSetUp is BaseScript {
    function run() public virtual broadcast {
          deployAndSet();
    }

    function deployAndSet() internal {
        string memory networkName = getNetworkName();
        address authority = readConfigAddr(networkName, "Authority");
        console.log("Authority address:", authority);
        uint256 chainId = block.chainid;
        if(chainId == 212 || chainId == 22776) {
               deployRelay(networkName, authority);
               deployPeriphery(networkName, authority);
               deployGasService(networkName, authority);
               deployProtocolFee(networkName, authority);
               deployRegistry(networkName, authority);
               deployVaultManager(networkName, authority);
               setUp(networkName);
        } else {
               deployGateway(networkName, authority);
        }
    }

   function deployRelay(string memory networkName, address authority) internal returns(Relay relay) {
        string memory salt = vm.envString("GATEWAY_SALT"); 
        Relay impl = new Relay();
        bytes memory initData = abi.encodeWithSelector(Relay.initialize.selector, authority);
        address r = deployProxyByFactory(salt, address(impl), initData);
        relay = Relay(r);

        console.log("Relay address:", r);
        saveConfig(networkName, "Relay", r);

        address wToken = readConfigAddr(networkName, "wToken");
        relay.setWtoken(wToken);
        console.log("wToken address:", wToken);

   }

    function deployGateway(string memory networkName, address authority) internal returns(Gateway gateway) {
        string memory salt = vm.envString("GATEWAY_SALT"); 
        Gateway impl = new Gateway();
        bytes memory initData = abi.encodeWithSelector(Gateway.initialize.selector, authority);
        address g = deployProxyByFactory(salt, address(impl), initData);
        gateway = Gateway(g);

        console.log("Gateway address:", g);
        saveConfig(networkName, "Gateway", g);

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
        saveConfig(networkName, "VaultManager", v);
   }

    function deployProtocolFee(string memory networkName, address authority) internal returns(ProtocolFee protocolFee) {
        ProtocolFee impl = new ProtocolFee();
        bytes memory initData = abi.encodeWithSelector(ProtocolFee.initialize.selector, authority);
        address p = deployProxy(address(impl), initData);
        protocolFee = ProtocolFee(payable(p));

        console.log("ProtocolFee address:", p);
        saveConfig(networkName, "ProtocolFee", p);
   }

   function deployPeriphery(string memory networkName, address authority) internal returns(Periphery periphery) {
        Periphery impl = new Periphery();
        bytes memory initData = abi.encodeWithSelector(Periphery.initialize.selector, authority);
        address p = deployProxy(address(impl), initData);
        periphery = Periphery(p);

        console.log("Periphery address:", p);
        saveConfig(networkName, "Periphery", p);
   }

    function deployRegistry(string memory networkName, address authority) internal returns(Registry registry) {
        Registry impl = new Registry();
        bytes memory initData = abi.encodeWithSelector(Registry.initialize.selector, authority);
        address r = deployProxy(address(impl), initData);
        registry = Registry(r);

        console.log("Registry address:", r);
        saveConfig(networkName, "Registry", r);
   }

   function deployGasService(string memory networkName, address authority) internal returns(GasService gasService) {
        GasService impl = new GasService();
        bytes memory initData = abi.encodeWithSelector(GasService.initialize.selector, authority);
        address g = deployProxy(address(impl), initData);
        gasService = GasService(g);

        console.log("GasService address:", g);
        saveConfig(networkName, "GasService", g);
   }

    function deployViewController(string memory networkName, address authority) internal returns(ViewController viewController) {
        ViewController impl = new ViewController();
        bytes memory initData = abi.encodeWithSelector(ViewController.initialize.selector, authority);
        address v = deployProxy(address(impl), initData);
        viewController = ViewController(v);

        console.log("ViewController address:", v);
        saveConfig(networkName, "ViewController", v);
   }

   function setUp(string memory networkName) internal {
        address relay_addr = readConfigAddr(networkName, "Relay");
        console.log("Relay address:", relay_addr);
        address vaultManager_addr = readConfigAddr(networkName, "VaultManager");
        console.log("VaultManager address:", vaultManager_addr);
        address periphery_addr = readConfigAddr(networkName, "Periphery");
        console.log("Periphery address:", periphery_addr);
        address protocolFee_addr = readConfigAddr(networkName, "ProtocolFee");
        console.log("ProtocolFee address:", protocolFee_addr);
        address gasService_addr = readConfigAddr(networkName, "GasService");
        console.log("GasService address:", gasService_addr);
        address registry_addr = readConfigAddr(networkName, "Registry");
        console.log("Registry address:", registry_addr);

        address TSSManager = readConfigAddr(networkName, "TSSManager");
        console.log("TSSManager address:", TSSManager);

        Relay r = Relay(relay_addr);
        r.setVaultManager(vaultManager_addr);
        r.setPeriphery(periphery_addr);

        VaultManager v = VaultManager(vaultManager_addr);
        v.setRelay(relay_addr);
        v.setPeriphery(periphery_addr);

        GasService g = GasService(gasService_addr);
        g.setPeriphery(periphery_addr);

        Periphery p = Periphery(periphery_addr);
        p.setRelay(relay_addr);
        p.setGasService(gasService_addr);
        p.setVaultManager(vaultManager_addr);
        p.setTSSManager(TSSManager);
        p.setTokenRegister(registry_addr);
        p.setProtocolFeeManager(protocolFee_addr);
        address swapManager = readConfigAddr(networkName, "SwapManager");
        address affiliateManager = readConfigAddr(networkName, "AffiliateManager");
        p.setAffiliateManager(affiliateManager);
        p.setSwapManager(swapManager);
   }

   function upgrade(string memory c) internal {
     string memory networkName = getNetworkName();
     if(keccak256(bytes(c)) == keccak256(bytes("Relay"))) {
          address relay_addr = readConfigAddr(networkName, "Relay");
          Relay r = Relay(relay_addr);
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
     } else if(keccak256(bytes(c)) == keccak256(bytes("Periphery"))) {
          address periphery_addr = readConfigAddr(networkName, "Periphery");
          Periphery p = Periphery(periphery_addr);
          Periphery impl = new Periphery();
          p.upgradeToAndCall(address(impl), bytes(""));
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
          Gateway g = Gateway(gateway_addr);
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