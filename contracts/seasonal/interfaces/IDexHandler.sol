// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IDexHandler {
    function getBalance(address wallet) external view returns (int256);
}
