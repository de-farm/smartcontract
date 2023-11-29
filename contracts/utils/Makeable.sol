// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./Errors.sol";

abstract contract Makeable is OwnableUpgradeable {
    event MakerChanged(address indexed maker);

    // Address used for signing during the creation of a new farm.
    address private _maker;

    function __Makeable_init() internal onlyInitializing {
        _maker = owner();
    }

    /// @notice set the maker address
    /// @dev can only be called by the `owner`
    /// @param _newMaker the admin address
    function setMaker(address _newMaker) external onlyOwner {
        if (_newMaker == address(0)) revert ZeroAddress();
        _maker = _newMaker;
        emit MakerChanged(_newMaker);
    }

    function maker() public view returns(address) {
        return _maker;
    }
}
