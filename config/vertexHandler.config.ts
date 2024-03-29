export interface ChainConfig {
    quote: string;
    querier?: string; // https://vertex-protocol.gitbook.io/docs/developer-resources/contracts
    endpoint?: string;
    slowModeFee?: string;
}

export const getChainConfig = (networkName: string): ChainConfig => {
    switch(networkName) {
        case "arbitrumSepolia":
            return {
                quote: '0xbC47901f4d2C5fc871ae0037Ea05c3F614690781', // USDC
                querier: '0x2F579046eC1e88Ff580ca5ED9373e91ece8894b0',
                endpoint : '0xaDeFDE1A14B6ba4DA3e82414209408a49930E8DC',
                slowModeFee: '1000000', // 1e6
            }
        case "blastSepolia":
            return {
                quote: '0xbC47901f4d2C5fc871ae0037Ea05c3F614690781', // USDC
                querier: '0xae557AEf1C7290252BA390589C717b9355017fD4',
                endpoint : '0xDFA3926296eaAc8E33c9798836Eae7e8CA1B02FB',
                slowModeFee: '1000000', // 1e6
            }
        case "blast":
            return {
                quote: '0x4300000000000000000000000000000000000003', // USDB
                querier: '0x24367B4f22dD406C8BaC3fc54bd5bD0E0d9C56F1',
                endpoint : '0x00F076FE36f2341A1054B16ae05FcE0C65180DeD',
                slowModeFee: '1000000000000000000', // 1e6
            }
        default:
            return {
                quote: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
                querier: '0x1693273B443699bee277eCbc60e2C8027E91995d',
                endpoint : '0xbbEE07B3e8121227AfCFe1E2B82772246226128e',
                slowModeFee: '1000000', // 1e6
            }
    }
}