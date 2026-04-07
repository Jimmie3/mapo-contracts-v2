import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "dotenv/config";
import "./tasks/index";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      evmVersion: "london"
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache_hardhat",
    artifacts: "./artifacts"
  },
  networks: {
    hardhat: {
      chainId: 31337
    },
    Tron: {
      url: process.env.TRON_RPC_URL || "https://api.trongrid.io/jsonrpc",
      chainId: 728126428,
      accounts: process.env.TRON_PRIVATE_KEY ? [process.env.TRON_PRIVATE_KEY] : [],
    },
    Tron_test: {
      url: "https://api.nileex.io/jsonrpc",
      chainId: 3448148188,
      accounts: process.env.TESTNET_PRIVATE_KEY ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD"
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
    alwaysGenerateOverloads: false,
    externalArtifacts: ["externalArtifacts/*.json"],
    dontOverrideCompile: false
  }
};

export default config;