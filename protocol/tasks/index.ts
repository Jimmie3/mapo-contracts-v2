import "./subs/Gateway";
import "./subs/vaultManager";
import "./subs/vaultToken";
import "./subs/registry";
import "./subs/protocolFee";
import "./subs/gasService";
import "./subs/relay";


import { task } from "hardhat/config";
import { getDeploymentByKey } from "./subs/utils"


task("upgrade", "upgrade contract")
  .addParam("contract", "contract name")
  .setAction(async (taskArgs, hre) => {
      const { network, ethers } = hre;
      let [wallet] = await ethers.getSigners();
      console.log("wallet address is: ", await wallet.getAddress());
      const ContractFactory = await ethers.getContractFactory(taskArgs.contract);
      let addr = await getDeploymentByKey(network.name, taskArgs.contract);
      if(!addr || addr.length === 0) throw("contract not deploy");
      // cast to any so TypeScript allows calling deploy on the generated factory
      let impl = await (await (ContractFactory as any).deploy()).waitForDeployment();

      let c = await ethers.getContractAt("BaseImplementation", addr, wallet);
      console.log(`pre impl `, await c.getImplementation());
      await(await c.upgradeToAndCall(await impl.getAddress(), "0x")).wait();
      console.log(`after impl `, await c.getImplementation());
  })

// steps
// 1. deploy contract
// 2. set up contract   
// 3. gateway and relay -> gateway:updateTokens
// 4. relay -> relay:addAllChain
// 5. vaultManager -> vaultManager:updateVaultFeeRate
// 6. vaultManager -> vaultManager:updateBalanceFeeRate
// 7. vaultManager -> vaultManager:registerToken
// 8. vaultManager -> vaultManager:updateAllTokenWeights
// 9. registry -> registry:registerAllChain
// 10. registry -> registry:registerAllToken
// 11. registry -> registry:mapAllToken
// 12.registry -> registry:setAllTokenNickname