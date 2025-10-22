import { ethers, network } from "hardhat";

import {
 Registry,
 Relay,
 Periphery,
 GasService,
 Gateway,
 VaultManager,
 VaultToken,
 ProtocolFee
} from "../typechain-types/contracts"

import { ViewController } from "../typechain-types/contracts/len"
import { MockToken } from "../typechain-types/contracts/mocks";

let authority = ""


async function main() {

   let [wallet] = await ethers.getSigners();
   console.log("wallet:", await wallet.getAddress());

}

async function deploy(contract:string) {

  let c =  await deployProxy(contract);
  console.log(`${contract} deployed to: ${c}`);
  
}

async function deployProxy(impl:string, ) {
    let I = await ethers.getContractFactory(impl);
    let i = await (await I.deploy()).waitForDeployment();
    let init_data = I.interface.encodeFunctionData("initialize", [authority]);
    let ContractProxy = await ethers.getContractFactory("ERC1967Proxy");
    let c = await (await ContractProxy.deploy(await i.getAddress(), init_data)).waitForDeployment();
    console.log(await c.getAddress());
    return c.getAddress();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.log(error);
        process.exit(1);
    });
