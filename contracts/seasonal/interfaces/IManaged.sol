// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IManaged {
  function manager() external view returns (address);

  function isMemberAllowed(address member) external view returns (bool);
}
