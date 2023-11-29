// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interfaces/IManaged.sol";

abstract contract Managed is IManaged, Initializable {
  using SafeMathUpgradeable for uint256;

  event ManagerUpdated(address newManager);
  event MemberAdded(address);
  event MemberRemoved(address);

  address public manager;

  address[] private _memberList;
  mapping(address => uint256) private _memberPosition;

  function __Managed_init(address _manager) internal onlyInitializing {
    require(_manager != address(0), "Invalid manager address");

    manager = _manager;
  }

  modifier onlyManager() {
    require(msg.sender == manager, "only manager");
    _;
  }

  function isMemberAllowed(address member) public view returns (bool) {
    return _memberPosition[member] != 0;
  }

  function getMembers() external view returns (address[] memory) {
    return _memberList;
  }

  function changeManager(address newManager) public onlyManager {
    require(newManager != address(0), "Invalid manager address");

    manager = newManager;

    emit ManagerUpdated(newManager);
  }

  function addMembers(address[] memory members) external onlyManager {
    for (uint256 i = 0; i < members.length; i++) {
      if (isMemberAllowed(members[i])) continue;

      _addMember(members[i]);
    }
  }

  function removeMembers(address[] memory members) external onlyManager {
    for (uint256 i = 0; i < members.length; i++) {
      if (!isMemberAllowed(members[i])) continue;

      _removeMember(members[i]);
    }
  }

  function addMember(address member) external onlyManager {
    if (isMemberAllowed(member)) return;

    _addMember(member);
  }

  function removeMember(address member) external onlyManager {
    if (!isMemberAllowed(member)) return;

    _removeMember(member);
  }

  function numberOfMembers() external view returns (uint256) {
    return _memberList.length;
  }

  function _addMember(address member) internal {
    _memberList.push(member);
    _memberPosition[member] = _memberList.length;
    emit MemberAdded(member);
  }

  function _removeMember(address member) internal {
    uint256 length = _memberList.length;
    uint256 index = _memberPosition[member].sub(1);

    address lastMember = _memberList[length.sub(1)];

    _memberList[index] = lastMember;
    _memberPosition[lastMember] = index.add(1);
    _memberPosition[member] = 0;

    _memberList.pop();

    emit MemberRemoved(member);
  }
}
