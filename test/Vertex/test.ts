import { JsonRpcProvider, Wallet } from 'ethers';
import {createVertexClient} from '@vertex-protocol/client';
import * as contracts from '@vertex-protocol/contracts';
import BigNumber from 'bignumber.js';

/**
 * Create a VertexClient object
 */
async function main() {
  // Create a signer connected to Sopelia testnet
  const signer = new Wallet(
    "", // add private key, or import, or use .env
    new JsonRpcProvider(
      'https://sepolia-rollup.arbitrum.io/rpc	',
      {
        name: 'arbitrum-sopelia',
        chainId: 421614,
      },
    ),
  );

  // Instantiate the main Vertex client
  const vertexClient = await createVertexClient('testnet', {
    signerOrProvider: signer,
  });

  // const signerAddress = signer.address
  const signerAddress = '0xFA51cd8bc8B56B9737E5086Bef3B0Dd5e03eDCD0'

  const subaccountID = await vertexClient.subaccount.getSubaccountId({name: 'default', address: signerAddress})
  /* const summary = await vertexClient.subaccount.getSubaccountSummary({subaccountName: 'default', subaccountOwner: signer.address});
  console.log(res.balances.map((x) => x.amount.toNumber())); */

  // https://github.com/vertex-protocol/vertex-typescript-sdk/blob/main/packages/contracts/src/utils/bytes32.ts
  const subaccountBytes32 = contracts.subaccountToBytes32({
      subaccountOwner: signerAddress,
      subaccountName: 'default'
  })

  console.log(subaccountBytes32);
  const hex = contracts.subaccountToHex({
      subaccountOwner: signerAddress,
      subaccountName: 'default'
  })

  console.log(hex);

  const subAccountSummaryContract = await contracts.getSubaccountSummary({
    subaccountOwner: signerAddress,
    subaccountName: 'default',
    querier: vertexClient.context.contracts.querier
  })

  const totalContract = contracts.calcTotalPortfolioValues(subAccountSummaryContract)
  console.log('netTotal', totalContract.netTotal.toString());
  console.log('totalNotional', totalContract.totalNotional.toString());

  const subAccountSummaryApi = await vertexClient.subaccount.getEngineSubaccountSummary({
    subaccountOwner: signerAddress,
    subaccountName: 'default'
  })

  const ONE_DOLLAR = new BigNumber(1e18)
  const totalApi = contracts.calcTotalPortfolioValues(subAccountSummaryApi)
  console.log(totalApi.netTotal);
  console.log(totalApi.totalNotional.div(ONE_DOLLAR).toNumber());

  try {
  await vertexClient.spot.withdraw({
    subaccountOwner: signerAddress,
    subaccountName: 'default',
    productId: 0,
    amount: 10,
    nonce: '1'
  })
}catch(e) { console.log(e)}
}

main();