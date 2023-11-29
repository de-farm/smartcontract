// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IHasPausable {
  function isPaused() external view returns (bool);
}
