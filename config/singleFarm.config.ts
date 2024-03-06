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
                dexHandler: '0xd218db8496729413ca5cb5Ad4DC34078863E66cc',
                deFarmSeeds: '0x704bBd3665D16B765d73648d8015cDa1Fe2cb185'
            }
            break
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
        minInvestmentAmount: parseUnits("10", chainConfig.usdDecimals),
        maxInvestmentAmount: parseUnits("1000", chainConfig.usdDecimals),
        maxLeverage: parseUnits("10", 6),
        admin: '0x91D02f1803BE80f62d7B7d4d031c0E9d778bc3e3',
        usdToken: chainConfig.usdToken,
        baseTokens: chainConfig.baseTokens.map(token => token.address),
        dexHandler: chainConfig.dexHandler,
        deFarmSeeds: chainConfig.deFarmSeeds
    }
}
