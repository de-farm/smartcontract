import { ethers } from "hardhat"
import { parseUnits } from "ethers"

export interface ChainConfig {
    usdToken: string;
    usdDecimals: number;
    baseTokens: {address: string, decimals: number}[];
}

export const getChainConfig = (networkName: string): ChainConfig => {
    switch(networkName) {
        case "arbitrumGoerli":
            return {
                usdToken: '0x179522635726710Dd7D2035a81d856de4Aa7836c',
                usdDecimals: 6,
                baseTokens: [
                    {
                        // WETH
                        address: '0xCC59686e3a32Fb104C8ff84DD895676265eFb8a6',
                        decimals: 18,
                    },
                    {
                        // WBTC
                        address: '0x5Cc7c91690b2cbAEE19A513473D73403e13fb431',
                        decimals: 18,
                    },
                ]
            }
            break
        case "optimisticGoerli":
            return {
                usdToken: '0xe5e0de0abfec2fffac167121e51d7d8f57c8d9bc',
                usdDecimals: 6,
                baseTokens: [
                    {
                        address: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270',
                        decimals: 18,
                    }
                ]
            }
            break
        default:
            return {
                usdToken: '0xe5e0de0abfec2fffac167121e51d7d8f57c8d9bc',
                usdDecimals: 6,
                baseTokens: [
                    {
                        address: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270',
                        decimals: 18,
                    }
                ]
            }
    }
}

export interface SingeFarmConfig {
    capacityPerFarm: bigint;
    minInvestmentAmount: bigint;
    maxInvestmentAmount: bigint;
    maxLeverage: bigint;
    usdToken: string;
    baseTokens: string[];
    admin: string | undefined;
    maker: string | undefined;
    defarmSeeds: string;
}

export const getSingleFarmConfig = (networkName: string): SingeFarmConfig => {
    const chainConfig = getChainConfig(networkName)

    return {
        capacityPerFarm: parseUnits("5000", chainConfig.usdDecimals),
        minInvestmentAmount: parseUnits("10", chainConfig.usdDecimals),
        maxInvestmentAmount: parseUnits("1000", chainConfig.usdDecimals),
        maxLeverage: parseUnits("10", 6),
        admin: '0xf58FcFb8ccDb1878823Bd6b473d7799468ACeBf5',
        maker: '0xb66c1e96a3675bbfb8d13df329033f84a3c00c9f',
        usdToken: chainConfig.usdToken,
        baseTokens: chainConfig.baseTokens.map(token => token.address),
        defarmSeeds: '0x67549b8c83666dFbaC60118CBdf5d6c4dB94F4e6'
    }
}
