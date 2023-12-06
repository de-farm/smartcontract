// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IOperatorManager.sol";

abstract contract OperatorManager is IOperatorManager, Initializable {
    event OperatorAdded(address);
    event OperatorRemoved(address);

    address public manager;

    address[] private _operators;
    mapping(address => uint256) private _indexes;

    function __OperatorManager_init(
        address _manager
    ) internal onlyInitializing {
        require(_manager != address(0), "Invalid manager address");
        manager = _manager;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "only manager");
        _;
    }

    function hasOperator(address op) public view returns (bool) {
        return _indexes[op] != 0;
    }

    function getOperators() public view returns (address[] memory) {
        return _operators;
    }

    function getOperator(uint256 index) public view returns (address) {
        require(index < _operators.length, "invalid index");
        return _operators[index];
    }

    function addOperator(address op) external onlyManager {
        if (hasOperator(op)) return;
        _addOperator(op);
    }

    function removeOperator(address op) external onlyManager {
        if (!hasOperator(op)) return;
        _removeOperator(op);
    }

    function removeOperators(address[] memory ops) external onlyManager {
        for (uint256 i = 0; i < ops.length; ++i) {
            if (hasOperator(ops[i])) continue;
            _removeOperator(ops[i]);
        }
    }

    function addOperators(address[] memory ops) external onlyManager {
        for (uint256 i = 0; i < ops.length; ++i) {
            if (hasOperator(ops[i])) continue;
            _addOperator(ops[i]);
        }
    }

    function numberOperators() public view returns (uint256) {
        return _operators.length;
    }

    function _addOperator(address op) internal {
        _operators.push(op);
        _indexes[op] = _operators.length;
        emit OperatorAdded(op);
    }

    function _removeOperator(address op) internal {
        uint256 len = _operators.length;
        uint256 index = _indexes[op] - 1;

        address last = _operators[len - 1];

        _operators[index] = last;
        _indexes[last] = index - 1;
        _indexes[op] = 0;

        _operators.pop();

        emit OperatorRemoved(op);
    }
}
