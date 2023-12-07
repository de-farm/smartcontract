export interface ChainConfig {
    whitelistedTokens: {
        asset: string;
        aggregator: string
    }[];
    maker?: string;
    dexHandler: string;
}

export const getChainConfig = (networkName: string): ChainConfig => {
    switch(networkName) {
        case "arbitrumSepolia":
            // https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum#Arbitrum%20Sopelia
            return {
                whitelistedTokens: [
                    { // USDC
                        asset: '0x179522635726710Dd7D2035a81d856de4Aa7836c',
                        aggregator: '0x1692Bdd32F31b831caAc1b0c9fAF68613682813b'
                    },
                    { // WETH
                        asset: '0xCC59686e3a32Fb104C8ff84DD895676265eFb8a6',
                        aggregator: '0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08'
                    },
                    { // WBTC
                        asset: '0x5Cc7c91690b2cbAEE19A513473D73403e13fb431',
                        aggregator: '0x6550bc2301936011c1334555e62A87705A81C12C'
                    }
                ],
                maker: '0xb66c1e96a3675bbfb8d13df329033f84a3c00c9f',
                dexHandler: '0x57c7C95CDC05D099991EBFd91171a75E0C35a1b5'
            }
        case "mainnet": return {
            whitelistedTokens: [
                { // USDC
                    asset: '0x0000000000000000000000000000000000000000',
                    aggregator: '0x0000000000000000000000000000000000000000'
                },
                { // WETH
                    asset: '0x0000000000000000000000000000000000000000',
                    aggregator: '0x0000000000000000000000000000000000000000'
                },
                { // WBTC
                    asset: '0x0000000000000000000000000000000000000000',
                    aggregator: '0x0000000000000000000000000000000000000000'
                }
            ],
            maker: '0x0000000000000000000000000000000000000000',
            dexHandler: '0x57c7C95CDC05D099991EBFd91171a75E0C35a1b5'
        }
        default:
            return {
                whitelistedTokens: [
                    { // USDC
                        asset: '0x179522635726710Dd7D2035a81d856de4Aa7836c',
                        aggregator: '0x1692Bdd32F31b831caAc1b0c9fAF68613682813b'
                    },
                    { // WETH
                        asset: '0xCC59686e3a32Fb104C8ff84DD895676265eFb8a6',
                        aggregator: '0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08'
                    },
                    { // WBTC
                        asset: '0x5Cc7c91690b2cbAEE19A513473D73403e13fb431',
                        aggregator: '0x6550bc2301936011c1334555e62A87705A81C12C'
                    }
                ],
                maker: '0xb66c1e96a3675bbfb8d13df329033f84a3c00c9f',
                dexHandler: '0xFc69d0f1d70825248C9F9582d13F93D60b6b56De'
            }
    }
}