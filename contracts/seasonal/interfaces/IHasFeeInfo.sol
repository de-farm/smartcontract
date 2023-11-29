// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IHasFeeInfo {
  function getMaximumManagerFee() external view returns (uint256, uint256);
  function getMaximumPerformanceFee() external view returns (uint256, uint256);
  function getMaximumEntranceFee() external view returns (uint256, uint256);
  function getMaximumExitFee() external view returns (uint256, uint256);
  function getPenaltyFee(uint256 day) external view returns (uint256, uint256);

  struct Fees {
    uint256 management;
    uint256 performance;
    uint256 entrance;
    uint256 exit;
  }
}
