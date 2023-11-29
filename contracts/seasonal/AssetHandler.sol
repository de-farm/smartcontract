// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IAssetHandler.sol";

/**
 * @title deFarm Asset Price Feeds
 * @dev Returns Chainlink USD price feed with 18 decimals(Chainlink direct USD price feed with 8 decimals)
 */
contract AssetHandler is IAssetHandler, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    event AssetAdded(address asset, address aggregator);
    event AssetRemoved(address asset);
    event ChainlinkTimeoutSet(uint256 _chainlinkTimeout);

    struct Asset {
        address asset;
        address aggregator;
    }

    uint256 public chainlinkTimeout; // Chainlink oracle timeout period
    mapping(address => address) public override priceAggregators; // Asset Mappings

    function initialize(Asset[] memory assets) external initializer {
        __Ownable_init();

        chainlinkTimeout = 90000; // 25 hours
        addAssets(assets);
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Currenly only use chainlink price feed.
     * @dev Calculate the USD price of a given asset.
     * @param asset the asset address
     * @return price Returns the latest price of a given asset (decimal: 18)
     */
    function getUSDPrice(address asset) external view override returns (uint256 price) {
        address aggregator = priceAggregators[asset];

        require(aggregator != address(0), "Price aggregator not found");

        if(block.chainid == 31337) {
            price = uint256(1).mul(10**18);
        }
        else {
            AggregatorV3Interface dataFeed = AggregatorV3Interface(aggregator);

            try dataFeed.latestRoundData() returns (
                uint80, // roundID
                int256 _price,
                uint256, // startedAt
                uint256 updatedAt, // timeStamp
                uint80 // answeredInRound
            ) {
                // check chainlink price updated within chainlinkTimeout value
                require(updatedAt.add(chainlinkTimeout) >= block.timestamp, "Chainlink price expired");

                if (_price > 0) {
                    price = uint256(_price).mul(10**10); // convert Chainlink decimals 8 -> 18
                }
            } catch {
                revert("Price get failed");
            }
        }

        require(price > 0, "Price not available");
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Setting the timeout for the Chainlink price feed
    /// @param newTimeoutPeriod A new time in seconds for the timeout
    function setChainlinkTimeout(uint256 newTimeoutPeriod) external onlyOwner {
        chainlinkTimeout = newTimeoutPeriod;
        emit ChainlinkTimeoutSet(newTimeoutPeriod);
    }

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
}
