import { ethers } from "hardhat"
import { parseUnits } from "ethers"

export interface ChainConfig {
    usdToken: string;
    usdDecimals: number;
    baseTokens: string[];
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
                    '0x94B3173E0a23C28b2BA9a52464AC24c2B032791c',
                    '0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82',
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
                    '0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82' // WETH
                ],
                dexHandler: '0xD9ff83b4AE13EA581d4e4c078Fa7b0d7c3fAdB1d',
                deFarmSeeds: '0x1c50b7145d5D542c73a5b0ecC7b751aCDf9BE929'
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
                dexHandler: '0x91b275A7211A276755b7aCB9A0fDA297EAA5F0fe',
                deFarmSeeds: '0xA549Bdccc03800Ff382D3977Fc7dE546c20d16a8'
            }
        case "arbitrumOne":
            return {
                usdToken: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
                usdDecimals: 6,
                baseTokens: [
                    '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
                    '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
                ],
                dexHandler: '0xe7730965068C33e4CbAaAd73ddd3270A0A5AF24a',
                deFarmSeeds: '',
            }
        default:
            return {
                usdToken: '',
                usdDecimals: 18,
                baseTokens: [
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
        minInvestmentAmount: parseUnits("10", chainConfig.usdDecimals),
        maxInvestmentAmount: parseUnits("5000", chainConfig.usdDecimals),
        maxLeverage: parseUnits("20", 6),
        admin: '0x6dC8592BfA5002DC1E043516B582F282dD568bdA',
        usdToken: chainConfig.usdToken,
        baseTokens: chainConfig.baseTokens,
        dexHandler: chainConfig.dexHandler,
        deFarmSeeds: chainConfig.deFarmSeeds
    }
}
