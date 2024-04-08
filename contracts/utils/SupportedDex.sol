// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/ISupportedDex.sol";
import "./Errors.sol";

abstract contract SupportedDex is OwnableUpgradeable, ISupportedDex {
    event DexRouterSet(address dexRouter);

    address public dexRouter;

    function __SupportedDex_init(
        address _dexRouter
    ) internal onlyInitializing {
        _setDexRouter(_dexRouter);
    }

    function setDexRouter(address _dexRouter) external onlyOwner {
        _setDexRouter(_dexRouter);
    }

    function _setDexRouter(address _dexRouter) internal {
        require(_dexRouter != address(0), "Invalid DEX handler address");

        dexRouter = _dexRouter;

        emit DexRouterSet(dexRouter);
    }
}
