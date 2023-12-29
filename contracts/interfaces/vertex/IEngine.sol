// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IEngine {
    struct Balance {
        int128 amount;
        int128 lastCumulativeMultiplierX18;
    }

    /// @notice Returns the balance of a subaccount given a product ID.
    function getBalance(
        uint32 productId,
        bytes32 subaccount
    ) external view returns (Balance memory);
}
