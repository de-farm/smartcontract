// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
interface IHasProtocolInfo {
  function treasury() external view returns (address);
  function getProtocolFee() external view returns (uint256, uint256);
}
