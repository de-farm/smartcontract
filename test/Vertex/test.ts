import { JsonRpcProvider, Wallet } from 'ethers';
import {createVertexClient} from '@vertex-protocol/client';
import * as contracts from '@vertex-protocol/contracts';
import BigNumber from 'bignumber.js';

/**
 * Create a VertexClient object
 */
async function main() {
  // Create a signer connected to Goerli testnet
  const signer = new Wallet(
    "4e131a5cdd7543d1eb473caffbfa38c98135cb259bac93ec936779e427992108", // add private key, or import, or use .env
    new JsonRpcProvider(
      'https://goerli-rollup.arbitrum.io/rpc',
      {
        name: 'arbitrum-goerli',
        chainId: 421613,
      },
    ),
  );

  // Instantiate the main Vertex client
  const vertexClient = await createVertexClient('testnet', {
    signerOrProvider: signer,
  });

  const signerAddress = signer.address
  // const signerAddress = '0xcc5Fb9F31C6F5A080430194fDf68E3308B753eF9'

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
}

main();