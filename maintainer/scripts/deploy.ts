import { ethers } from "hardhat";

import {Maintainers, TSSManager, Parameters} from "../typechain-types/contracts";



async function main() {
    let [wallet] = await ethers.getSigners();
    console.log("wallet address: ", await wallet.getAddress()); 

}


main()
    .then()
    .catch((error) => {
        console.log(error);
        process.exit(1);
    });
