// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IDeFarmSeeds.sol";

contract DeFarmSeeds is IDeFarmSeeds, OwnableUpgradeable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public subjectFeePercent;

    event ProtocolFeePercentChanged(uint256 feePercent);
    event SubjectFeePercentChanged(uint256 feePercent);
    event Trade(address trader, address subject, bool isBuy, uint256 seedAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 subjectEthAmount, uint256 supply);

    // SeedsSubject => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public seedsBalance;

    // SeedsSubject => Supply
    mapping(address => uint256) public seedsSupply;

    function initialize() public initializer {
        __Ownable_init();

        protocolFeeDestination = owner();
    }

    function setProtocolFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
        emit ProtocolFeePercentChanged(protocolFeePercent);
    }

    function setSubjectFeePercent(uint256 _feePercent) public onlyOwner {
        subjectFeePercent = _feePercent;
        emit SubjectFeePercentChanged(subjectFeePercent);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1 )* (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getBuyPrice(address seedsSubject, uint256 amount) public view returns (uint256) {
        return getPrice(seedsSupply[seedsSubject], amount);
    }

    function getSellPrice(address seedsSubject, uint256 amount) public view returns (uint256) {
        return getPrice(seedsSupply[seedsSubject] - amount, amount);
    }

    function getBuyPriceAfterFee(address seedsSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(seedsSubject, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        return price + protocolFee + subjectFee;
    }

    function getSellPriceAfterFee(address seedsSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(seedsSubject, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        return price - protocolFee - subjectFee;
    }

    function balanceOf(address holder, address seedsSubject) public view override returns (uint256) {
        return seedsBalance[seedsSubject][holder];
    }

    function buySeeds(address seedsSubject, uint256 amount) public payable {
        uint256 supply = seedsSupply[seedsSubject];
        require(supply > 0 || seedsSubject == msg.sender, "Only the seeds' subject can buy the first seed");
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        seedsBalance[seedsSubject][msg.sender] = seedsBalance[seedsSubject][msg.sender] + amount;
        seedsSupply[seedsSubject] = supply + amount;
        emit Trade(msg.sender, seedsSubject, true, amount, price, protocolFee, subjectFee, supply + amount);
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = seedsSubject.call{value: subjectFee}("");
        require(success1 && success2, "Unable to send funds");
    }

    function sellSeeds(address seedsSubject, uint256 amount) public payable {
        uint256 supply = seedsSupply[seedsSubject];
        require(supply > amount, "Cannot sell the last seed");
        require(msg.sender != seedsSubject || seedsBalance[seedsSubject][msg.sender] > amount, "Cannot sell the first seed");
        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        require(seedsBalance[seedsSubject][msg.sender] >= amount, "Insufficient seeds");
        seedsBalance[seedsSubject][msg.sender] = seedsBalance[seedsSubject][msg.sender] - amount;
        seedsSupply[seedsSubject] = supply - amount;
        emit Trade(msg.sender, seedsSubject, false, amount, price, protocolFee, subjectFee, supply - amount);
        (bool success1, ) = msg.sender.call{value: price - protocolFee - subjectFee}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success3, ) = seedsSubject.call{value: subjectFee}("");
        require(success1 && success2 && success3, "Unable to send funds");
    }
}