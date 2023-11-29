// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ISpotEngine {
    struct Config {
        address token;
        int128 interestInflectionUtilX18;
        int128 interestFloorX18;
        int128 interestSmallCapX18;
        int128 interestLargeCapX18;
    }

    struct State {
        int128 cumulativeDepositsMultiplierX18;
        int128 cumulativeBorrowsMultiplierX18;
        int128 totalDepositsNormalized;
        int128 totalBorrowsNormalized;
    }

    struct Balance {
        int128 amount;
        int128 lastCumulativeMultiplierX18;
    }

    struct BalanceNormalized {
        int128 amountNormalized;
    }

    struct LpState {
        int128 supply;
        Balance quote;
        Balance base;
    }

    struct LpBalance {
        int128 amount;
    }

    struct Balances {
        BalanceNormalized balance;
        LpBalance lpBalance;
    }
}
