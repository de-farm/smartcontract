// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

interface IOperatorManager {
    function manager() external view returns (address);

    function getOperators() external view returns (address[] memory);

    function getOperator(uint256 index) external view returns (address);

    function numberOperators() external view returns (uint256);

    function hasOperator(address op) external view returns (bool);

    function addOperator(address op) external;

    function removeOperator(address op) external;

    function addOperators(address[] memory ops) external;

    function removeOperators(address[] memory ops) external;
}
