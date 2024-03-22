//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IDeFarmSeeds.sol";

interface IDeFarmSeedsActions is IDeFarmSeeds {
    function buySeeds(address seedsSubject, uint256 amount, uint256 factor) external;
    function sellSeeds(address seedsSubject, uint256 amount) external;
    function getBuyPriceAfterFee(address seedsSubject, uint256 amount) external view returns (uint256);
}