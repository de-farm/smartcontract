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
    arbitrumGoerli : {
      url: `https://arbitrum-goerli.infura.io/v3/1dc76974d45041a399877518073f43cc`,
      chainId: 421613,
      accounts: process.env.OWNER_PRIVATE_KEY
        ?[
          process.env.OWNER_PRIVATE_KEY,
        ]:[],
    },
    optimisticGoerli : {
      chainId: 420,
      url: process.env.GOERLI_OPT_URL || "https://goerli.optimism.io/",
      accounts: process.env.OWNER_PRIVATE_KEY
        ?[
          process.env.OWNER_PRIVATE_KEY,
        ]:[],
    },
  },
  etherscan: {
    apiKey: {
      optimisticGoerli : process.env.ETHERSCAN_API_KEY || "8KT8WRN5IR3B4UUQVDQBR23YAA2E7KG7PP",
      arbitrumGoerli : process.env.ARBISCAN_API_KEY || "Q64QDZTGG8Q5R97T6E2K2ZD2638NDSPFKM",
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
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
      "SeasonalFarmFactory",
      "SeasonalFarm",
      "FarmManagement",
      "AssetHandler",
      "AssetSimulator",
      "VertexHandler",
      "DexSimulator",
      "DeFarmSeeds"
    ],
    spacing: 2,
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
