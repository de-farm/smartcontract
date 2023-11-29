// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./interfaces/IAssetHandler.sol";

/**
 * @title deFarm Asset Price Feeds
 * @dev To simulate the prices of assets
 */
contract AssetSimulator is IAssetHandler, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    event AssetAdded(address asset, address aggregator);
    event AssetRemoved(address asset);

    struct Asset {
        address asset;
        address aggregator;
    }

    mapping(address => address) public override priceAggregators; // Asset Mappings
    mapping(address => uint256) public priceAssets;

    function initialize(Asset[] memory assets) external initializer {
        __Ownable_init();

        addAssets(assets);
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Calculate the USD price of a given asset.
     * @param asset the asset address
     * @return price Returns the latest price of a given asset (decimal: 18)
     */
    function getUSDPrice(address asset) external view override returns (uint256 price) {
        address aggregator = priceAggregators[asset];

        require(aggregator != address(0), "Price aggregator not found");

        price = priceAssets[aggregator];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Add valid asset with price aggregator
    /// @param asset Address of the asset to add
    /// @param aggregator Address of the aggregator
    function addAsset(address asset, address aggregator) public onlyOwner {
        require(asset != address(0), "asset address cannot be 0");
        require(aggregator != address(0), "aggregator address cannot be 0");

        priceAggregators[asset] = aggregator;

        emit AssetAdded(asset, aggregator);
    }

    /// @notice Add valid assets with price aggregator
    /// @param assets An array of assets to add
    function addAssets(Asset[] memory assets) public onlyOwner {
        for (uint8 i = 0; i < assets.length; i++) {
            addAsset(assets[i].asset, assets[i].aggregator);
        }
    }

    /// @notice Remove valid asset
    /// @param asset Address of the asset to remove
    function removeAsset(address asset) external onlyOwner {
        priceAggregators[asset] = address(0);

        emit AssetRemoved(asset);
    }

    function updatePrice(address asset, uint256 price) external onlyOwner {
        address aggregator = priceAggregators[asset];
        require(aggregator != address(0), "Price aggregator not found");

        priceAssets[aggregator] = price;
    }
}
