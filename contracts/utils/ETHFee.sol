// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IHasETHFee.sol";
import "./Errors.sol";

abstract contract ETHFee is OwnableUpgradeable, IHasETHFee {
    // fee from the manager to pay for operator transactions (default - 1e16)
    uint256 private _ethFee;

    function __ETHFee_init() internal onlyInitializing {
        _ethFee = 1e16;
    }

    /// @notice set the eth fee to collect the transaction gas from the manager
    /// @dev can only be called by the `owner`
    /// @param newEthFee eth fee
    function setEthFee(uint256 newEthFee) external onlyOwner {
        _ethFee = newEthFee;
        emit EthFeeChanged(newEthFee);
    }

    function ethFee() public override view returns(uint256) {
        return _ethFee;
    }
}
