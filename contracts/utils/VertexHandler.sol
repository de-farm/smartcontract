// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./Errors.sol";
import "../interfaces/vertex/IEndpoint.sol";
import "../interfaces/vertex/IFQuerier.sol";
import "../interfaces/IDexHandler.sol";

struct LinkSigner {
    bytes32 sender;
    bytes32 signer;
    uint64 nonce;
}

struct WithdrawCollateral {
    bytes32 sender;
    uint32 productId;
    uint128 amount;
    uint64 nonce;
}

contract VertexHandler is Initializable, IDexHandler {
    using SafeMathUpgradeable for int256;

    // name is 'default'
    bytes12 constant DEFAULT_SUBACCOUNT = hex"64656661756c740000000000";

    address public vertexEndpoint;
    address public vertexQuerier;

    function initialize(address _vertexEndpoint, address _vertexQuerier) external initializer {
        vertexEndpoint = _vertexEndpoint;
        vertexQuerier = _vertexQuerier;
    }

    // https://github.com/vertex-protocol/vertex-typescript-sdk/blob/main/packages/contracts/src/utils/bytes32.ts#L14
    function addressToSubaccount(address wallet) public pure returns (bytes32) {
        // 32 bytes, name is 'default'
        return bytes32(abi.encodePacked(wallet, DEFAULT_SUBACCOUNT));
    }

    function findSpotProductId(address asset) public view returns(uint32) {
        IFQuerier querier = IFQuerier(vertexQuerier);
        IFQuerier.ProductInfo memory productInfo = querier.getAllProducts();

        for (uint32 i = 0; i < productInfo.spotProducts.length; i++) {
            IFQuerier.SpotProduct memory spotProduct = productInfo.spotProducts[i];
            if(spotProduct.config.token == asset) {
                return spotProduct.productId;
            }
        }

        revert InvalidAddress(asset);
    }

    // Deposit to Vertex
    // https://vertex-protocol.gitbook.io/docs/developer-resources/api/depositing
    function depositInstruction(
        address asset,
        uint256 amount
    ) external view override returns(address, bytes memory) {
        if(amount > type(uint128).max) revert AboveMax(type(uint128).max, amount);
        uint32 productId = findSpotProductId(asset);

        bytes memory data = abi.encodeWithSignature(
            "depositCollateral(bytes12,uint32,uint128)",
            DEFAULT_SUBACCOUNT, productId, uint128(amount)
        );

        return (vertexEndpoint, data);
    }

    function linkSignerInstruction(address farm, address operator) external view returns(address, bytes memory) {
        LinkSigner memory linkSigner = LinkSigner({
            sender: addressToSubaccount(farm),
            signer: bytes32(uint256(uint160(operator)) << 96),
            nonce: 0
        });

        // https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/interfaces/IEndpoint.sol#L31
        bytes memory data = abi.encodePacked(uint8(19), abi.encode(linkSigner));
        bytes memory instruction = abi.encodeWithSignature("submitSlowModeTransaction(bytes)", data);
        return (vertexEndpoint, instruction);
    }

    function withdrawInstruction(address farm, address asset, uint256 amount) external view returns(address, bytes memory) {
        if(amount > type(uint128).max) revert AboveMax(type(uint128).max, amount);

        WithdrawCollateral memory withdrawal = WithdrawCollateral({
            sender: addressToSubaccount(farm),
            productId: findSpotProductId(asset),
            amount: uint128(amount),
            nonce: 0
        });
        // https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/interfaces/IEndpoint.sol#L14
        bytes memory data = abi.encodePacked(uint8(2), abi.encode(withdrawal));
        bytes memory instruction = abi.encodeWithSignature("submitSlowModeTransaction(bytes)", data);

        return (vertexEndpoint, instruction);
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
