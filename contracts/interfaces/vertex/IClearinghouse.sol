// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IClearinghouse {
    /// @notice Retrieve quote ERC20 address.
    function getQuote() external view returns (address);

    /// @notice Retrieve the engine of a product.
    function getEngineByProduct(
        uint32 productId
    ) external view returns (address);

    /// @notice Gets the price of a product.
    function getOraclePriceX18(
        uint32 productId
    ) external view returns (uint256);
}
