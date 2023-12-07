import { ethers } from "hardhat"
import { parseUnits } from "ethers"

export interface ChainConfig {
    usdToken: string;
    usdDecimals: number;
    baseTokens: {address: string, decimals: number}[];
    dexHandler: string;
    defarmSeeds: string;
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
                dexHandler: '0xDe922034e83694eF01261bdA646038de50f2EFf5',
                defarmSeeds: '0x16bfC2c47902C4F2904655342AfFC48Aa2DE8A45'
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
                defarmSeeds: ''
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
    dexHandler: string;
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
        defarmSeeds: chainConfig.defarmSeeds,
        dexHandler: chainConfig.dexHandler
    }
}
