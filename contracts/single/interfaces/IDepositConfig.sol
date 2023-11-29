//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDepositConfig {
    function minInvestmentAmount() external view returns (uint256);
    function maxInvestmentAmount() external view returns (uint256);
    function capacityPerFarm() external view returns (uint256);
}