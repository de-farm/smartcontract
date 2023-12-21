//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

error AboveMax(uint256 max, uint256 given);
error BelowMin(uint256 min, uint256 given);
error ZeroAddress();
error ZeroAmount();
error ZeroTokenBalance();
error ZeroSeedBalance();
error NoAccess(address desired, address given);
error InvalidSignature(address desired);
error InvalidAddress(address given);
error InvalidLength(uint256 desired);
error MakeInstructionFailure();
error ExecutionCallFailure();
error HasLinkSigner();
error HasClosedFundraising();
error InvalidToken(address token);
error FeeTooHigh(uint256 fee);
error NotEnoughFund();