// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
interface ISupportedDex {
  function dexHandler() external view returns (address);
  function getPair(address token0, address token1) external view returns(address);
}
