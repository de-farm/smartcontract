// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./vertex/IFQuerier.sol";
import "./interfaces/IDexHandler.sol";

contract VertexHandler is OwnableUpgradeable, IDexHandler {
    using SafeMathUpgradeable for int256;

    address public vertexQuerier;

    function initialize(address _vertexQuerier) external initializer {
        __Ownable_init();

        vertexQuerier = _vertexQuerier;
    }

    // https://github.com/vertex-protocol/vertex-typescript-sdk/blob/main/packages/contracts/src/utils/bytes32.ts#L14
    function addressToSubaccount(address wallet) public pure returns (bytes32) {
        // 32 bytes, name is 'default'
        bytes memory byteArray = hex"000000000000000000000000000000000000000064656661756c740000000000";
        uint160 addressBytes = uint160(wallet);
        for (uint8 i = 0; i < 20; i++) {
            byteArray[i] = bytes1(uint8(addressBytes / (2**(8*(19 - i)))));
        }

        return bytes32(byteArray);
    }

    // https://github.com/vertex-protocol/vertex-typescript-sdk/blob/main/packages/contracts/src/utils/subaccountInfo.ts#L42
    function getBalance(address wallet) external view returns (int256 balance) {
        bytes32 subaccount = addressToSubaccount(wallet);
        IFQuerier querier = IFQuerier(vertexQuerier);
        IFQuerier.ProductInfo memory productInfo = querier.getAllProducts();

        balance = 0;

        for (uint32 i = 0; i < productInfo.spotProducts.length; i++) {
            IFQuerier.SpotProduct memory spotProduct = productInfo.spotProducts[i];
            IFQuerier.SpotBalance memory spotBalance = querier.getSpotBalance(subaccount, spotProduct.productId);

            balance += calcSpotBalanceValue(
                spotBalance,
                spotProduct
            );
            balance += calcSpotLpSpotBalanceValue(
                spotBalance,
                spotProduct
            );
        }

        for (uint32 i = 0; i < productInfo.perpProducts.length; i++) {
            IFQuerier.PerpProduct memory perpProduct = productInfo.perpProducts[i];
            IFQuerier.PerpBalance memory perpBalance = querier.getPerpBalance(subaccount, perpProduct.productId);

            balance += calcPerpBalanceValue(
                perpBalance,
                perpProduct
            );
            balance += calcPerpLpBalanceValue(
                perpBalance,
                perpProduct
            );
        }
    }

    function calcSpotBalanceValue(
        IFQuerier.SpotBalance memory spotBalance,
        IFQuerier.SpotProduct memory spotProduct
    ) internal pure returns(int256 balance) {
        balance = int256(spotBalance.balance.amount)*int256(spotProduct.oraclePriceX18)/1e18;
    }

    function calcSpotLpSpotBalanceValue(
        IFQuerier.SpotBalance memory spotBalance,
        IFQuerier.SpotProduct memory spotProduct
    ) internal pure returns(int256 balance) {
        if(spotBalance.lpBalance.amount == 0) {
            balance = 0;
        }
        else {
            balance = calcSpotLpTokenValue(spotProduct)*spotBalance.lpBalance.amount;
        }
    }

    function calcPerpLpBalanceValue(
        IFQuerier.PerpBalance memory perpBalance,
        IFQuerier.PerpProduct memory perpProduct
    ) internal pure returns(int256 balance) {
        if(perpBalance.lpBalance.amount == 0) {
            balance = 0;
        }
        else {
            balance = calcPerpLpTokenValue(perpProduct)*perpBalance.lpBalance.amount;
        }
    }

    function calcSpotLpTokenValue(
        IFQuerier.SpotProduct memory spotProduct
    ) internal pure returns (int256) {
        if (spotProduct.lpState.supply == 0) {
            return 0;
        }

        int256 baseValue = int256(spotProduct.lpState.base.amount)
            /spotProduct.lpState.supply
            *spotProduct.oraclePriceX18;

        int256 quoteValue = int256(spotProduct.lpState.quote.amount)/spotProduct.lpState.supply;

        return baseValue + quoteValue;
    }

    function calcPerpLpTokenValue(
        IFQuerier.PerpProduct memory perpProduct
    ) internal pure returns (int256) {
        if (perpProduct.lpState.supply == 0) {
            return 0;
        }

        int256 baseValue = int256(perpProduct.lpState.base)
            /perpProduct.lpState.supply
            *perpProduct.oraclePriceX18;

        int256 quoteValue = int256(perpProduct.lpState.quote)/perpProduct.lpState.supply;

        return baseValue + quoteValue;
    }

    function calcPerpBalanceValue(
        IFQuerier.PerpBalance memory perpBalance,
        IFQuerier.PerpProduct memory perpProduct
    ) internal pure returns(int256 balance) {
        /* balanceWithProduct.amount
            .multipliedBy(balanceWithProduct.oraclePrice)
            .plus(balanceWithProduct.vQuoteBalance); */
        balance = int256(perpBalance.balance.amount)*int256(perpProduct.oraclePriceX18)/1e18 + perpBalance.balance.vQuoteBalance;
    }
}
