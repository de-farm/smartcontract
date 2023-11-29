// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IDexHandler.sol";

contract DexSimulator is OwnableUpgradeable, IDexHandler {
    mapping(address => int256) public balances;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setBalance(address wallet, int256 balance) external {
        balances[wallet] = balance;
    }

    function getBalance(address wallet) external view returns (int256) {
        return balances[wallet];
    }
}
