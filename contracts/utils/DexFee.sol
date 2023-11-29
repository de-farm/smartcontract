// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IHasDexFee.sol";
import "./Errors.sol";

abstract contract DexFee is OwnableUpgradeable, IHasDexFee {
    // fee to pay for DEX transactions (default - $1e6)
    uint256 public override feePerTx;
    address public override quote;

    function __DexFee_init(address _quote) internal onlyInitializing {
        quote = _quote;
        feePerTx = 1e6;
    }

    function setFeePerTx(uint256 newFeePerTx) external onlyOwner {
        feePerTx = newFeePerTx;
    }
}
