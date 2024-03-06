import { ethers } from "hardhat"
import { parseUnits } from "ethers"

export interface ChainConfig {
    usdToken: string;
    usdDecimals: number;
    baseTokens: {address: string, decimals: number}[];
    dexHandler: string;
    deFarmSeeds: string;
}

export const getChainConfig = (networkName: string): ChainConfig => {
    switch(networkName) {
        case "arbitrumSepolia":
            return {
                usdToken: '0xbC47901f4d2C5fc871ae0037Ea05c3F614690781',
                usdDecimals: 6,
                baseTokens: [
                    {
                        // WETH
                        address: '0x94B3173E0a23C28b2BA9a52464AC24c2B032791c',
                        decimals: 18,
                    },
                    {
                        // WBTC
                        address: '0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82',
                        decimals: 18,
                    },
                ],
                dexHandler: '0x6E5Ead7745407a7E16AD27C43c3D5D5f308cE96e',
                deFarmSeeds: ''
            }
            break
        case "blastSepolia":
            return {
                usdToken: '0xbC47901f4d2C5fc871ae0037Ea05c3F614690781',
                usdDecimals: 6,
                baseTokens: [
                    {
                        // WETH
                        address: '0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82',
                        decimals: 18,
                    },
                ],
                dexHandler: '0x47dB5B0947DeeA19ac3656Ce5B60b1525AF74415',
                deFarmSeeds: '0x704bBd3665D16B765d73648d8015cDa1Fe2cb185'
            }
        case "arbitrumOne":
            return {
                usdToken: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
                usdDecimals: 6,
                baseTokens: [
                    {
                        // WETH
                        address: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
                        decimals: 18,
                    },
                    {
                        // WBTC
                        address: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
                        decimals: 8,
                    },
                ],
                dexHandler: '0xe7730965068C33e4CbAaAd73ddd3270A0A5AF24a',
                deFarmSeeds: '',
            }
        default:
            return {
                usdToken: '',
                usdDecimals: 6,
                baseTokens: [
                    {
                        address: '',
                        decimals: 18,
                    }
                ],
                dexHandler: '',
                deFarmSeeds: ''
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
    dexHandler: string;
    deFarmSeeds: string;
}

export const getSingleFarmConfig = (networkName: string): SingeFarmConfig => {
    const chainConfig = getChainConfig(networkName)

    return {
        capacityPerFarm: parseUnits("5000", chainConfig.usdDecimals),
        minInvestmentAmount: parseUnits("20", chainConfig.usdDecimals),
        maxInvestmentAmount: parseUnits("2000", chainConfig.usdDecimals),
        maxLeverage: parseUnits("20", 6),
        admin: '0x4ff6Aabf3d2181d485676560c8fb79c587Fb0eaD',
        usdToken: chainConfig.usdToken,
        baseTokens: chainConfig.baseTokens.map(token => token.address),
        dexHandler: chainConfig.dexHandler,
        deFarmSeeds: chainConfig.deFarmSeeds
    }
}
