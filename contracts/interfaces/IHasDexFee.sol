// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
interface IHasDexFee {
  // function getTotalFee() external view returns (uint256);
  function quote() external view returns (address);
  function feePerTx() external view returns (uint256);
  event DexFeeChanged(uint256 ethFee);
}
