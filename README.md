# DeFarm
deFarm is a new type of Social Finance platform that truly mixes the best of both worlds together. Our aim is to provide a social platform that encourages LPs to meet with Asset Managers, and cooperate with each other to achieve maximum capital efficiency.

Speaking in simple terms/Layman Language, deFarm allows Fund Managers to create smart-contract based DeFi Vaults, which act like secured funds. Liquidity Providers can entrust their funds into the hands of other Funds Managers to earn passive income without the need to worry about the safety of their money.

## Repository
* `contracts/interfaces`: all interfaces using in defarm contract.
* `contracts/single`: contract handle logic of single farm, allow a farm manager create a farm with given config and manage position of farm with a dex.
* `contracts/utils`: all utilities contracts and libraries. In particular, It's contain a contract mapping to a Vertex contract (`VertexHandler`) and handle view data and submit transaction from a farm to Vertex.

We have 3 main contracts:

1. `SingleFarmFactory`: Contract for managers create a creating new single farm instance.
2. `SingleFarm`: Contract for the investors to deposit and for managers to open and close position.
3. `VertexHandler`: Contract integrating with Vertex contract for a query position information and deposit/withdraw fund to Vertex.

## Sequence of Events
A `SingleFarmFactory` is contract allows managers create multiple instance of single farm. It also manages a list of `operators`. The `operator` is responsible for manage Vertex position and deposit/withdraw fund through the Vertex API. On the other hand, Vertex allows to have one linked signer per SingleFarm — A linked signer can perform any execute on behalf of the subaccount it is linked to. 
Link: https://vertex-protocol.gitbook.io/docs/developer-resources/api/integrate-via-smart-contracts
### 1. Create Farm
* The entry point `createFarm` in `SingleFarmFactory` contract allows manager create a instance of single farm and assign a operator to a farm.

### 2. Deposit
* The entry point `deposit` in `SingleFarm` contract allows investors deposit fund to the farm when farm is not canceled or fundraising is not ended.

### 3. Close Fundraising
* The entry point `closeFundraising` in `SingleFarm` contract allows the manager to close the fundraising and open a position later. It also get payment fee from Vertex and hold the fee in farm.
### 4. Set Link Signer
* `setLinkSigner` allows the single farm address link signer to a operator. It submit a `LinkSinger` tx to Vertex using `submitSlowModeTransaction`.
### 6. Open Position
* `openPosition` allows the single farm deposit the raised fund to Vertex subaccount through `depositCollateral` of Vertex contract.
### 7. Close Position
* `closePosition` allows the single farm withdraw collateral of Vertex subaccount to single farm contract. It required a signature from operator for ensure the posotion has closed in Vertex.
### 8. Cancel
* Cancel the farm and investor can claim fund later.
### 10. Claim
* Transfers the collateral to the investor.

## Build
```bash
yarn compile
```


## Configuration
See example in `config/*.config.ts`


## Deploy
* Before deploy contract, you need ensure add enviroment variable in `.env` (see `.env.example`)
* Deploy VertexHandler on Arbitrum Sepolia
```bash
yarn deploy:VertexHandler:arbitrumSepolia
```
* Deploy SingleFarmFactory on Arbitrum Sepolia
```bash
yarn deploy:SingleFarm:arbitrumSepolia
```

