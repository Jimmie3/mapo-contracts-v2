// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScript, console} from "./Base.s.sol";
import {Maintainers} from "../../contracts/Maintainers.sol";
import {Parameters} from "../../contracts/Parameters.sol";
import {TSSManager} from "../../contracts/TSSManager.sol";


contract DeployAndSetUp is BaseScript {

    function run() public virtual broadcast {
          deploy();
          // set();
    }

    function deploy() internal returns (Parameters parameters, Maintainers maintainers, TSSManager manager) {
        address authority = readDeployment("Authority");
        console.log("Authority address:", authority);
        parameters = deployParameters(authority);
        maintainers = deployMaintainer(authority);
        manager = deployTSSManager(authority);
    }

    function set() internal {
        setUp();
        setUpParameters();
    }

   function deployMaintainer(address authority) internal returns(Maintainers maintainers) {
        bytes memory initData = abi.encodeWithSelector(Maintainers.initialize.selector, authority);
        (address m, address impl) = deployProxy(type(Maintainers).creationCode, initData);
        maintainers = Maintainers(payable(m));

        console.log("Maintainers address:", m);
        console.log("Maintainers implementation:", impl);
        saveDeployment("Maintainers", m);
   }

   function deployParameters(address authority) internal returns(Parameters parameters) {
        bytes memory initData = abi.encodeWithSelector(Parameters.initialize.selector, authority);
        (address p, address impl) = deployProxy(type(Parameters).creationCode, initData);
        parameters = Parameters(p);

        console.log("Parameters address:", p);
        console.log("Parameters implementation:", impl);
        saveDeployment("Parameters", p);
   }

    function deployTSSManager(address authority) internal returns(TSSManager manager) {
        bytes memory initData = abi.encodeWithSelector(TSSManager.initialize.selector, authority);
        (address m, address impl) = deployProxy(type(TSSManager).creationCode, initData);
        manager = TSSManager(m);

        console.log("TSSManager address:", m);
        console.log("TSSManager implementation:", impl);
        saveDeployment("TSSManager", m);
   }

   function setUp() internal {
        address maintainer_addr = readDeployment("Maintainers");
        console.log("Maintainers address:", maintainer_addr);
        address manager_addr = readDeployment("TSSManager");
        console.log("TSSManager address:", manager_addr);
        address parameters_addr = readDeployment("Parameters");
        console.log("Parameters address:", parameters_addr);
        address relay_addr = readDeployment("Relay");
        console.log("Relay address:", relay_addr);

        Maintainers m = Maintainers(payable(maintainer_addr));
        m.set(manager_addr, parameters_addr);

        TSSManager t = TSSManager(manager_addr);
        t.set(maintainer_addr, relay_addr, parameters_addr);
   }

    struct Config {
        string key;
        uint256 value;
    }

   function setUpParameters() internal {
          address parameters_addr = readDeployment("Parameters");
          Parameters p = Parameters(parameters_addr);
          string memory json = vm.readFile("config/parameters.json");
          bytes memory data = vm.parseJson(json);
          Config[] memory configs = abi.decode(data, (Config[]));
          for (uint i = 0; i < configs.length; i++) {
               console.log("Key: %s, Value: %s", configs[i].key, configs[i].value);
               p.set(configs[i].key, configs[i].value);
          }
   }

   function upgrade(string memory c) internal {
          if(keccak256(bytes(c)) == keccak256(bytes("Parameters"))){
               address parameters_addr = readDeployment("Parameters");
               deployAndUpgrade(parameters_addr, type(Parameters).creationCode);
          } else if(keccak256(bytes(c)) == keccak256(bytes("Maintainers"))) {
               address maintainers_addr = readDeployment("Maintainers");
               deployAndUpgrade(maintainers_addr, type(Maintainers).creationCode);
          } else {
               address manager_addr = readDeployment("TSSManager");
               deployAndUpgrade(manager_addr, type(TSSManager).creationCode);
          }
   }

   function updateMaintainerLimit(uint256 limit) internal {
          address maintainers_addr = readDeployment("Maintainers");
          Maintainers maintainer = Maintainers(payable(maintainers_addr));
          maintainer.updateMaintainerLimit(limit);
   }
}
