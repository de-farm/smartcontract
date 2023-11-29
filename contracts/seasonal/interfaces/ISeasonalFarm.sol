// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface ISeasonalFarm {
  struct Order {
    address asset;
    uint256 amount;
    bool isOpenning;
  }

  struct FarmInfo {
    bool isPrivate; // A boolean indicating whether the farm is private or not
    string name;
    string symbol;
    uint256 farmingPeriod; // If this value is zero, the farm is unlimited
    uint256 minDeposit;
    uint256 maxDeposit;
    uint256 initialLockupPeriod;
  }

  function factory() external view returns (address);
  function operator() external view returns (address);
  function farmManagement() external view returns (address);
  function endTime() external view returns (uint256);

  function setFarmManagement(address _farmManagement) external returns (bool);
}
