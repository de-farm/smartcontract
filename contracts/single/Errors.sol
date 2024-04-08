//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

error StillFundraising(uint256 desired, uint256 given);
error NoBaseToken(address token);
error AlreadyOpened();
error CantClose();
error NotOpened();
error NotFinalised();
error OpenPosition();
error NoOpenPositions();
error CantClosePosition();
error NotAbleLiquidate(uint256 fund);