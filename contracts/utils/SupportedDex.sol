// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/ISupportedDex.sol";
import "./Errors.sol";
import "../interfaces/thruster/IThrusterFactory.sol";

abstract contract SupportedDex is OwnableUpgradeable, ISupportedDex {
    event DexHandlerSet(address dexHandler);

    address public dexHandler;

    function __SupportedDex_init(address _dexHandler) internal onlyInitializing {
        _setDexHandler(_dexHandler);
    }

    /// @notice Set the dex handler address
    /// @param _dexHandler The address of the dex handler
    function setDexHandler(address _dexHandler) external onlyOwner {
        _setDexHandler(_dexHandler);
    }

    /// @notice Set the dex handler address internal call
    /// @param _dexHandler The address of the dex handler
    function _setDexHandler(address _dexHandler) internal {
        require(_dexHandler != address(0), "Invalid DEX handler address");

        dexHandler = _dexHandler;

        emit DexHandlerSet(dexHandler);
    }

    function getPair(address token0, address token1) public view returns(address) {
        IThrusterFactory factory = IThrusterFactory(dexHandler);
        address pair = factory.getPair(token0, token1);

        return pair;
    }
}
