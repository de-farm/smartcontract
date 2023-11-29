// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IFarmManagement {
    function factory() external view returns (address);
    function farm() external view returns (address);
    function isDepositAsset(address asset) external view returns (bool);
    function getManagementFee() external view returns (uint256, uint256);
    function getPerformanceFee() external view returns (uint256, uint256);
    function getEntranceFee() external view returns (uint256, uint256);
    function getExitFee() external view returns (uint256, uint256);
    function totalFundValue() external view returns (uint256);
}
