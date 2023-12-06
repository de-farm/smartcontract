// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IDexHandler {
    function getPaymentFee() external view returns(address, uint256);
    function getBalance(address wallet) external view returns (int256);
    function getBalance(address wallet, address token) external view returns (uint256);
    function depositInstruction(address asset, uint256 amount) external view returns(address, bytes calldata);
    function linkSignerInstruction(address farm, address operator) external view returns(address, bytes calldata);
    function withdrawInstruction(address farm, address asset, uint256 amount) external view returns(address, bytes calldata);
}
