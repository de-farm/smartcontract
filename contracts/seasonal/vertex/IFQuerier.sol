// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./ISpotEngine.sol";
import "./IPerpEngine.sol";

interface IFQuerier {
    struct SpotBalance {
        uint32 productId;
        ISpotEngine.LpBalance lpBalance;
        ISpotEngine.Balance balance;
    }

    struct PerpBalance {
        uint32 productId;
        IPerpEngine.LpBalance lpBalance;
        IPerpEngine.Balance balance;
    }

    struct Risk {
        int128 longWeightInitialX18;
        int128 shortWeightInitialX18;
        int128 longWeightMaintenanceX18;
        int128 shortWeightMaintenanceX18;
        int128 largePositionPenaltyX18;
    }

    // for config just go to the chain
    struct SpotProduct {
        uint32 productId;
        int128 oraclePriceX18;
        Risk risk;
        ISpotEngine.Config config;
        ISpotEngine.State state;
        ISpotEngine.LpState lpState;
        BookInfo bookInfo;
    }

    struct PerpProduct {
        uint32 productId;
        int128 oraclePriceX18;
        Risk risk;
        IPerpEngine.State state;
        IPerpEngine.LpState lpState;
        BookInfo bookInfo;
    }

    struct BookInfo {
        int128 sizeIncrement;
        int128 priceIncrementX18;
        int128 minSize;
        int128 collectedFees;
        int128 lpSpreadX18;
    }

    struct ProductInfo {
        SpotProduct[] spotProducts;
        PerpProduct[] perpProducts;
    }

    function getAllProducts() external view returns (ProductInfo memory);

    function getSpotBalance(bytes32 subaccount, uint32 productId)
        external
        view
        returns (SpotBalance memory);

    function getPerpBalance(bytes32 subaccount, uint32 productId)
        external
        view
        returns (PerpBalance memory);
}