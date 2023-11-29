// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IHasAssetInfo {
  function isValidAsset(address asset) external view returns (bool);

  function getAssetPrice(address asset) external view returns (uint256);
  function assetValue(address asset, uint256 amount) external view returns (uint256);
  function balanceOnDex(address wallet) external view returns (int256);
  function convertValueToAsset(address asset, uint256 value) external view returns (uint256);

  function getMaximumSupportedAssetCount() external view returns (uint256);
}
