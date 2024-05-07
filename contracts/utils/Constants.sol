//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

bytes32 constant CREATE_FARM_HASH = keccak256("CreateFarm");
uint256 constant FEE_DENOMINATOR = 100e18;
bytes32 constant CLOSE_POSITION_HASH = keccak256("ClosePosition");
bytes32 constant CANCEL_BY_MANAGER_HASH = keccak256("CancelByManager");
bytes32 constant CANCEL_BY_ADMIN_HASH = keccak256("CancelByAdmin");