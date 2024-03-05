//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDeFarmSeeds {
    function balanceOf(address holder, address seedsSubject) external returns (uint256);
}