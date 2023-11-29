// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IWhitelistedTokens {
  function isTokenAllowed(address token) external view returns (bool);
}
