// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
interface IHasETHFee {
  function ethFee() external view returns (uint256);
  event EthFeeChanged(uint256 ethFee);
}
