// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IHasProtocolInfo.sol";
import "./Errors.sol";
import "./Constants.sol";

abstract contract ProtocolInfo is OwnableUpgradeable, IHasProtocolInfo {
    event TreasuryChanged(address indexed treasury);
    event ProtocolFeeChanged(uint256 protocolFee);

    // percentage of fees from the profits of the farm to the protocol (default - 5e18 (5%))
    uint256 internal protocolFee;
    address private _treasury;

    function __ProtocolInfo_init(uint256 _protocolFee) internal onlyInitializing {
        _treasury = owner();
        protocolFee = _protocolFee;
    }

    /// @notice set the treasury address
    /// @dev can only be called by the `owner`
    /// @param _newTreasury the treasury address
    function setTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert ZeroAddress();
        _treasury = _newTreasury;
        emit TreasuryChanged(_treasury);
    }

    /// @notice set the protocol fee percent to calculate the protocol fees on profits depending on the governance
    /// @dev can only be called by the `owner`
    /// @param newProtocolFee the percent which is used to calculate the protocol fees on profits
    function setProtocolFee(uint256 newProtocolFee) external onlyOwner {
        if (newProtocolFee > FEE_DENOMINATOR) revert AboveMax(FEE_DENOMINATOR, newProtocolFee);
        protocolFee = newProtocolFee;
        emit ProtocolFeeChanged(newProtocolFee);
    }

    function getProtocolFee() public view override returns(uint256, uint256) {
        return (protocolFee, FEE_DENOMINATOR);
    }

    function treasury() public view override returns(address) {
        return _treasury;
    }
}
