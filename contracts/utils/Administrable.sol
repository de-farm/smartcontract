// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IHasAdministrable.sol";
import "./Errors.sol";

abstract contract Administrable is OwnableUpgradeable, IHasAdministrable {
    event AdminChanged(address indexed admin);

    // address used by the backend bot to update the farms
    address private _admin;

    function __Administrable_init() internal onlyInitializing {
        _admin = owner();
    }

    /// @notice set the admin address
    /// @dev can only be called by the `owner`
    /// @param _newAdmin the admin address
    function setAdmin(address _newAdmin) external onlyOwner {
        if (_newAdmin == address(0)) revert ZeroAddress();
        _admin = _newAdmin;
        emit AdminChanged(_newAdmin);
    }

    function admin() public view override returns (address) {
        return _admin;
    }
}
