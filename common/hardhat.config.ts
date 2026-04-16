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

    Mapo_test: {
      chainId: 212,
      url: "https://testnet-rpc.maplabs.io",
      accounts: process.env.TESTNET_PRIVATE_KEY ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },

    Tron_test: {
      url: "https://nile.trongrid.io/jsonrpc",
      chainId: 3448148188,
      accounts: process.env.TESTNET_PRIVATE_KEY ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },

    Bsc_test: {
      url: "https://api.zan.top/bsc-testnet",
      chainId: 97,
      accounts: process.env.TESTNET_PRIVATE_KEY ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },

    Eth_test: {
      url: "https://eth-sepolia.api.onfinality.io/public",
      chainId: 11155111,
      accounts: process.env.TESTNET_PRIVATE_KEY ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },

    Mapo: {
      chainId: 22776,
      url: "https://rpc.maplabs.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Eth: {
      url: "https://eth-mainnet.public.blastapi.io",
      chainId: 1,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Bsc: {
      url: "https://bsc-rpc.publicnode.com",
      chainId: 56,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Base: {
      url: "https://1rpc.io/base",
      chainId: 8453,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Arb: {
      url: "https://arb-one.api.pocket.network",
      chainId: 42161,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Op: {
      url: "https://optimism-public.nodies.app",
      chainId: 10,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Uni: {
      url: "https://unichain.drpc.org",
      chainId: 130,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Pol: {
      url: "https://polygon.rpc.subquery.network/public",
      chainId: 137,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Xlayer: {
      url: "https://rpc.xlayer.tech",
      chainId: 196,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },

    Tron: {
      url: process.env.TRON_RPC_URL || "https://api.trongrid.io/jsonrpc",
      chainId: 728126428,
      accounts: process.env.TRON_PRIVATE_KEY ? [process.env.TRON_PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD"
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
