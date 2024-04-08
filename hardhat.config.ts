import dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import '@typechain/hardhat'
import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import "hardhat-abi-exporter";
import "@typechain/hardhat";

dotenv.config();

const config: HardhatUserConfig = {
  networks: {
    localhost: {
      chainId: 31337,
      url: "http://127.0.0.1:8545",
      timeout: 600000,
    },
    blastSepolia : {
      url: 'https://sepolia.blast.io',
      chainId: 168587773,
      accounts: process.env.OWNER_PRIVATE_KEY
        ?[
          process.env.OWNER_PRIVATE_KEY,
        ]:[],
    },
    blast : {
      url: 'https://rpc.ankr.com/blast',
      chainId: 81457,
      accounts: process.env.OWNER_PRIVATE_KEY
        ?[
          process.env.OWNER_PRIVATE_KEY,
        ]:[],
    }
  },
  etherscan: {
    apiKey: {
      blastSepolia : process.env.BLASTSCAN_API_KEY || "blast_sepolia",
      blast : process.env.BLASTSCAN_API_KEY || "",
    },
    customChains: [
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io/"
        }
      },
      {
        network: "blastSepolia",
        chainId: 168587773,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan",
          browserURL: "https://testnet.blastscan.io/"
        }
      },
      {
        network: "blast",
        chainId: 81457,
        urls: {
          apiURL: "https://api.blastscan.io/api",
          browserURL: "https://blastscan.io/"
        }
      }
    ]
  },
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          viaIR: true,
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  typechain: {
    outDir: "./types",
    target: "ethers-v6",
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    only: [
      "SingleFarmFactory",
      "SingleFarm",
    ],
    spacing: 2,
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
