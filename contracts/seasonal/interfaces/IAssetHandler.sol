// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IAssetHandler {
    function priceAggregators(address asset) external view returns (address);
    function getUSDPrice(address asset) external view returns (uint256);
}
