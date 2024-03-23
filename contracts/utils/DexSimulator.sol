// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IDexHandler.sol";
import "./Errors.sol";

contract DexSimulator is OwnableUpgradeable, IDexHandler {
    mapping(address => int256) public balances;
    mapping(address => address) public signers;

    address public feeToken;
    uint256 public feeAmount;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setSigner(address wallet, address signer) external onlyOwner {
        require(msg.sender == wallet);
        signers[wallet] = signer;
    }

    function setBalance(address wallet, int256 balance) external onlyOwner {
        balances[wallet] = balance;
    }

    function getBalance(address wallet) external view returns (int256) {
        return balances[wallet];
    }

    function getBalance(address wallet, address token) external view returns (uint256) {
        if (token == address(0)) revert InvalidToken(token);
        return uint256(balances[wallet]);
    }

    function deposit(
        address asset,
        uint256 amount
    ) external {
        if(asset != address(0)) {
            IERC20Upgradeable(asset).transferFrom(msg.sender, address(this), amount);
            balances[msg.sender] = balances[msg.sender] + int256(uint256(amount));
        }
    }

    function depositInstruction(
        address asset,
        uint256 amount
    ) external view override returns(address, bytes memory) {
        if(amount > type(uint128).max) revert AboveMax(type(uint128).max, amount);
        bytes memory instruction = abi.encodeWithSignature(
            "deposit(address,uint256)",
            asset, amount
        );

        return (address(this), instruction);
    }

    function withdraw(
        address farm,
        address asset,
        uint256 amount
    ) external {
        if(asset != address(0)) {
            IERC20Upgradeable(asset).transfer(farm, amount);
            balances[farm] = balances[farm] - int256(uint256(amount));
        }
    }

    function withdrawInstruction(address farm, address asset, uint256 amount) external view returns(address, bytes memory) {
        if(amount > type(uint128).max) revert AboveMax(type(uint128).max, amount);

        bytes memory instruction = abi.encodeWithSignature("withdraw(address,address,uint256)", farm, asset, amount);

        return (address(this), instruction);
    }

    function linkSignerInstruction(address farm, address operator) external view returns(address, bytes memory) {
        bytes memory instruction = abi.encodeWithSignature(
            "setSigner(address,address)",
            farm, operator
        );
        return (address(this), instruction);
    }

    function setPaymentFee(address _feeToken, uint256 _feeAmount) external onlyOwner {
        feeToken = _feeToken;
        feeAmount = _feeAmount;
    }

    function getPaymentFee() external view returns(address, uint256) {
        return (feeToken, feeAmount);
    }
}
