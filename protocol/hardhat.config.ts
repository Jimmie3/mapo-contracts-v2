import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import { HardhatUserConfig } from "hardhat/config";
import * as dotenv from "dotenv";
import "./tasks";
dotenv.config();



const config: HardhatUserConfig = {
  paths: {
    cache: "cache_hardhat"
  },
  solidity: {
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "london"
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },

    Mapo_test: {
      chainId: 212,
      url: "https://testnet-rpc.maplabs.io",
      accounts: process.env.TESTNET_PRIVATE_KEY !== undefined ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },

    Tron_test: {
      url: `https://nile.trongrid.io/jsonrpc`,
      chainId: 3448148188,
      accounts: process.env.TESTNET_PRIVATE_KEY !== undefined ? [process.env.TESTNET_PRIVATE_KEY] : [],
    },

    Eth_test: {
      url: `https://eth-sepolia.api.onfinality.io/public`,
      chainId: 11155111,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Bsc_test: {
      url: `https://api.zan.top/bsc-testnet`,
      chainId: 97,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Mapo: {
      chainId: 22776,
      url: "https://rpc.maplabs.io",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Eth: {
      url: "https://eth-mainnet.public.blastapi.io",
      chainId: 1,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Bsc: {
      url: `https://bsc-rpc.publicnode.com`,
      chainId: 56,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Base: {
      url: `https://1rpc.io/base`,
      chainId: 8453,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Arb: {
      url: `https://arb-one.api.pocket.network`,
      chainId: 42161,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Op: {
      url: `https://optimism-public.nodies.app`,
      chainId: 10,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Uni: {
      url: `https://unichain.drpc.org`,
      chainId: 130,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Pol: {
      url: `https://polygon.rpc.subquery.network/public`,
      chainId: 137,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Xlayer: {
      url: `https://rpc.xlayer.tech`,
      chainId: 196,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    Tron: {
      url: `https://api.trongrid.io/jsonrpc`,
      chainId: 728126428,
      accounts: process.env.TRON_PRIVATE_KEY !== undefined ? [process.env.TRON_PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      Mapo: " ",
      Eth: process.env.ETHERSCAN_API_KEY || "",
      Bsc: process.env.ETHERSCAN_API_KEY || "",
      Base: process.env.ETHERSCAN_API_KEY || "",
      Arb: process.env.ETHERSCAN_API_KEY || "",
      Op: process.env.ETHERSCAN_API_KEY || "",
      Uni: process.env.ETHERSCAN_API_KEY || "",
      Pol: process.env.ETHERSCAN_API_KEY || "",
      Xlayer: " ",
    },
    customChains: [
      {
        network: "Mapo",
        chainId: 22776,
        urls: {
          apiURL: "https://explorer-api.chainservice.io/api",
          browserURL: "https://explorer.mapprotocol.io"
        },
      },
      {
        network: "Eth",
        chainId: 1,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=1",
          browserURL: "https://etherscan.com/",
        },
      },
      {
        network: "Bsc",
        chainId: 56,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=56",
          browserURL: "https://bscscan.com/",
        },
      },

      {
        network: "Base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=8453",
          browserURL: "https://basescan.com/",
        },
      },

      {
        network: "Arb",
        chainId: 42161,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
          browserURL: "https://arbiscan.io/",
        },
      },
      {
        network: "Op",
        chainId: 10,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=10",
          browserURL: "https://optimistic.etherscan.io/",
        },
      },
      {
        network: "Uni",
        chainId: 130,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=130",
          browserURL: "https://uniscan.io/",
        },
      },
      {
        network: "Pol",
        chainId: 137,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=137",
          browserURL: "https://polygonscan.com/",
        },
      },
      {
        network: "Xlayer",
        chainId: 196,
        urls: {
          apiURL: "https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/xlayer",
          browserURL: "https://www.oklink.com",
        },
      },
    ]
  },
};

export default config;
