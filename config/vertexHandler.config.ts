export interface ChainConfig {
    quote: string;
    querier?: string; // https://vertex-protocol.gitbook.io/docs/developer-resources/contracts
    endpoint?: string;
}

export const getChainConfig = (networkName: string): ChainConfig => {
    switch(networkName) {
        case "arbitrumSopelia":
            return {
                quote: '0xbC47901f4d2C5fc871ae0037Ea05c3F614690781', // USDC
                querier: '0x2F579046eC1e88Ff580ca5ED9373e91ece8894b0',
                endpoint : '0xaDeFDE1A14B6ba4DA3e82414209408a49930E8DC'
            }
        case "mainnet": return {
            quote: '', // USDC
            querier: '0x1693273B443699bee277eCbc60e2C8027E91995d',
            endpoint : '0xbbEE07B3e8121227AfCFe1E2B82772246226128e'
        }
        default:
            return {
                quote: '',
                querier: '0x1693273B443699bee277eCbc60e2C8027E91995d',
                endpoint : '0xbbEE07B3e8121227AfCFe1E2B82772246226128e'
            }
    }
}