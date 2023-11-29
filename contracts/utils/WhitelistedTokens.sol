// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IWhitelistedTokens.sol";

abstract contract WhitelistedTokens is
    IWhitelistedTokens,
    OwnableUpgradeable
{
    using SafeMathUpgradeable for uint256;

    event TokenAdded(address asset);
    event TokenRemoved(address asset);

    address[] private _tokens;
    mapping(address => uint256) private _tokenPosition;

    function isTokenAllowed(address token) public view returns (bool) {
      return _tokenPosition[token] != 0;
    }

    function getTokens() external view returns (address[] memory) {
      return _tokens;
    }

    function addTokens(address[] memory tokens) external onlyOwner {
      _addTokens(tokens);
    }

    function _addTokens(address[] memory tokens) internal {
      for (uint256 i = 0; i < tokens.length; i++) {
        if (isTokenAllowed(tokens[i])) continue;

        _addToken(tokens[i]);
      }
    }

    function removeTokens(address[] memory tokens) external onlyOwner {
      for (uint256 i = 0; i < tokens.length; i++) {
        if (!isTokenAllowed(tokens[i])) continue;

        _removeToken(tokens[i]);
      }
    }

    function addToken(address token) external onlyOwner {
      if (isTokenAllowed(token)) return;

      _addToken(token);
    }

    function removeToken(address token) external onlyOwner {
      if (!isTokenAllowed(token)) return;

      _removeToken(token);
    }

    function numberOfTokens() external view returns (uint256) {
      return _tokens.length;
    }

    function _addToken(address token) internal {
      _tokens.push(token);
      _tokenPosition[token] = _tokens.length;

      emit TokenAdded(token);
    }

    function _removeToken(address token) internal {
        uint256 length = _tokens.length;
        uint256 index = _tokenPosition[token].sub(1);

        address lastMember = _tokens[length.sub(1)];

        _tokens[index] = lastMember;
        _tokenPosition[lastMember] = index.add(1);
        _tokenPosition[token] = 0;

        _tokens.pop();

        emit TokenRemoved(token);
    }
}
