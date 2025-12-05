// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { IFactory } from "./interfaces/IFactory.sol";
import { Script, stdJson, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "../../contracts/ERC1967Proxy.sol";



abstract contract BaseScript is Script {
    IFactory constant private factory = IFactory(0x6258e4d2950757A749a4d4683A7342261ce12471);
    using stdJson for string;
    address internal broadcaster;
    uint256 private broadcasterPK;
    constructor() {
        uint256 privateKey;
        if(block.chainid == 212) {
            privateKey = vm.envUint("TESTNET_PRIVATE_KEY");
        } else {
            privateKey = vm.envUint("PRIVATE_KEY");
        }

        broadcaster = vm.addr(privateKey);
        broadcasterPK = privateKey;
    }

    modifier broadcast() {
        vm.startBroadcast(broadcasterPK);
        _;
        vm.stopBroadcast();
    }

    function deployProxyByFactory(string memory salt, address impl, bytes memory initData) internal returns(address addr) {
        addr = deployByFactory(salt, type(ERC1967Proxy).creationCode, abi.encode(impl, initData));
    }

    function deployByFactory(string memory salt, bytes memory creationCode, bytes memory param) internal returns(address addr) {
        addr = factory.getAddress(keccak256(bytes(salt)));
        if(addr.code.length > 0 ) revert ("addr aready exist");
        bytes memory code = abi.encodePacked(creationCode, param);
        factory.deploy(keccak256(bytes(salt)), code, 0);
    }

    function deployProxy(address impl, bytes memory initData)  internal returns(address) {
        ERC1967Proxy p = new ERC1967Proxy(impl, initData);
        return address(p);
    }

    function readConfigAddr(string memory networkName, string memory key) internal view returns(address addr) {
        string memory configPath = "deployments/deploy.json";
        if (!vm.exists(configPath)) {
            revert(string(abi.encodePacked("Config file not found: ", configPath)));
        }
        string memory config = vm.readFile(configPath);
        string memory path = string(abi.encodePacked(".", networkName, ".", key));
        addr = config.readAddress(path);
    }

    function readConfigUint(string memory networkName, string memory key) internal view returns(uint256 v) {
        string memory configPath = "deployments/deploy.json";
        if (!vm.exists(configPath)) {
            revert(string(abi.encodePacked("Config file not found: ", configPath)));
        }
        string memory config = vm.readFile(configPath);
        string memory path = string(abi.encodePacked(".", networkName, ".", key));
        v = config.readUint(path);
    }

    function saveConfig(string memory networkName, string memory key, address addr) internal {
        string memory configPath = "deployments/deploy.json";
        string memory path = string(abi.encodePacked(".", networkName, ".", key));
        string memory json = vm.readFile(configPath);
        bool exists = vm.keyExistsJson(json, path);
        string memory addrStr = vm.toString(addr);
        if(exists) {
            vm.writeJson(addrStr, configPath, path);
        } else {
            revert(string(abi.encodePacked("key:", key, "not exists")));
        }
    }

    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if(chainId == 212) return "Makalu";
        if(chainId == 22776) return "Mapo";
        if(chainId == 1) return "Eth";
        if(chainId == 11155111) return "eth_test";
        if(chainId == 56) return "Bsc";
        if(chainId == 97) return "bsc_test";
        revert("unknown");
    }
}
