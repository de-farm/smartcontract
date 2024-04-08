import { ethers } from "hardhat"
import { parseUnits } from "ethers"

export interface ChainConfig {
    usdToken: string;
    usdDecimals: number;
    baseTokens: string[];
    deFarmSeeds: string;
    thrusterRouter: string;
}

export const getChainConfig = (networkName: string): ChainConfig => {
    switch(networkName) {
        case "blastSepolia":
            return {
                usdToken: '0x4200000000000000000000000000000000000022',
                usdDecimals: 18,
                baseTokens: [
                    '0x4200000000000000000000000000000000000023' // WETH
                ],
                deFarmSeeds: '0x1c50b7145d5D542c73a5b0ecC7b751aCDf9BE929',
                thrusterRouter: '0xEf52b983b902357e9aD4EF4C383b3eF28f5E74d5'
            }
        case "blast":
            return {
                usdToken: '0x4300000000000000000000000000000000000003',
                usdDecimals: 18,
                baseTokens: [
                    '0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f', //BTC
                    '0x82af49447d8a07e3bd95bd0d56f35241523fbab1', //ETH
                    '0x000000000000000000000000000000000000002b', //TIA
                    '0x000000000000000000000000000000000000003c', //MEME
                    '0x000000000000000000000000000000000000003a', //IMX
                    '0x0000000000000000000000000000000000000011', //OP
                    '0x912ce59144191c1204e64559fe8253a0e49e6548', //ARB
                    '0x0000000000000000000000000000000000000025', //DYDX
                    '0x0000000000000000000000000000000000000033', //AVAX
                    '0x0000000000000000000000000000000000000007', //BNB
                    '0x0000000000000000000000000000000000000041', //BLUR
                    '0x0000000000000000000000000000000000000059', //JUP
                    '0x000000000000000000000000000000000000000f', //SUI
                    '0x000000000000000000000000000000000000002d', //PYTH
                    '0x0000000000000000000000000000000000000049', //FIL
                    '0x0000000000000000000000000000000000000047', //LDO
                    '0x000000000000000000000000000000000000001d', //mPEPE
                    '0x0000000000000000000000000000000000000021', //DOGE
                    '0x000000000000000000000000000000000000001b', //MKR
                    '0x0000000000000000000000000000000000000045', //NEAR
                    '0x0000000000000000000000000000000000000027', //CRV
                    '0x0000000000000000000000000000000000000019', //COMP
                    '0x0000000000000000000000000000000000000017', //BCH
                    '0x0000000000000000000000000000000000000039', //ADA
                    '0x0000000000000000000000000000000000000037', //SNX
                    '0x0000000000000000000000000000000000000055', //ATOM
                    '0x0000000000000000000000000000000000000057', //APE
                    '0x0000000000000000000000000000000000000023', //LINK
                    '0x0000000000000000000000000000000000000053', //GALA
                    '0x0000000000000000000000000000000000000051', //TRX
                ],
                deFarmSeeds: '0xA549Bdccc03800Ff382D3977Fc7dE546c20d16a8',
                thrusterRouter: '0x98994a9A7a2570367554589189dC9772241650f6'
            }
        default:
            return {
                usdToken: '0x4300000000000000000000000000000000000003',
                usdDecimals: 18,
                baseTokens: [
                    '0x4200000000000000000000000000000000000023' // WETH
                ],
                deFarmSeeds: '0xb4A7D971D0ADea1c73198C97d7ab3f9CE4aaFA13',
                thrusterRouter: '0x98994a9A7a2570367554589189dC9772241650f6'
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
    deFarmSeeds: string;
    thrusterRouter: string;
}

export const getSingleFarmConfig = (networkName: string): SingeFarmConfig => {
    const chainConfig = getChainConfig(networkName)

    return {
        capacityPerFarm: parseUnits("10000", chainConfig.usdDecimals),
        minInvestmentAmount: parseUnits("10", chainConfig.usdDecimals),
        maxInvestmentAmount: parseUnits("10000", chainConfig.usdDecimals),
        maxLeverage: parseUnits("20", 6),
        admin: '0x6dC8592BfA5002DC1E043516B582F282dD568bdA',
        usdToken: chainConfig.usdToken,
        baseTokens: chainConfig.baseTokens,
        deFarmSeeds: chainConfig.deFarmSeeds,
        thrusterRouter: chainConfig.thrusterRouter
    }
}
