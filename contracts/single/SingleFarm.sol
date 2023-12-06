// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../utils/Constants.sol";
import "../utils/Errors.sol";
import "./Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISingleFarm} from "./interfaces/ISingleFarm.sol";
import {ISingleFarmFactory} from "./interfaces/ISingleFarmFactory.sol";
import {IDepositConfig} from "./interfaces/IDepositConfig.sol";
import "../interfaces/IHasOwnable.sol";
import {IHasAdministrable} from "../interfaces/IHasAdministrable.sol";
import "../interfaces/IHasPausable.sol";
import "../interfaces/IHasProtocolInfo.sol";
import "../interfaces/IHasSeedable.sol";
import "../seeds/IDeFarmSeeds.sol";
import "../interfaces/ISupportedDex.sol";
import "../interfaces/IDexHandler.sol";

/// @title SingleFarm
/// @notice Contract for the investors to deposit and for managers to open and close positions
contract SingleFarm is ISingleFarm, Initializable {
    bool private calledOpen;
    bool public isSeedsFarm;

    ISingleFarmFactory.Sf public sf;

    address public USDC;

    address public factory;
    address public manager; // Farm manager
    address public operator; // Dex external account with link signer
    uint256 public endTime;
    uint256 public fundDeadline;
    uint256 public totalRaised;
    uint256 public actualTotalRaised;
    SfStatus public status;
    uint256 public override remainingAmountAfterClose;
    mapping(address => uint256) public userAmount;
    mapping(address => uint256) public claimAmount;
    mapping(address => bool) public claimed;
    uint256 private managerFeeNumerator;

    bool isLinkSigner;
    uint256 maxFeePay;

    function initialize(
        ISingleFarmFactory.Sf calldata _sf,
        address _manager,
        uint256 _managerFee,
        address _usdc,
        address _operator
    ) public initializer {
        sf = _sf;
        factory = msg.sender;
        manager = _manager;
        managerFeeNumerator = _managerFee;
        operator = _operator;
        endTime = block.timestamp + _sf.fundraisingPeriod;
        fundDeadline = 72 hours;
        USDC = _usdc;
        isSeedsFarm = true;
        isLinkSigner = false;
        maxFeePay = 10000000; // 10e6
    }

    modifier onlyOwner() {
        require(msg.sender == IHasOwnable(factory).owner(), "only owner");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == IHasAdministrable(factory).admin(), "only admin");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "only manager");
        _;
    }

    modifier openOnce() {
        require(!calledOpen, "can only open once");
        calledOpen = true;
        _;
    }

    modifier whenNotPaused() {
        require(!IHasPausable(factory).isPaused(), "contracts paused");
        _;
    }

    /// @notice deposit a particular amount into a farm for the manager to open a position
    /// @dev `fundraisingPeriod` has to end and the `totalRaised` should not be more than `capacityPerFarm`
    /// @dev amount has to be between `minInvestmentAmount` and `maxInvestmentAmount`
    /// @dev approve has to be called before this method for the investor to transfer usdc to this contract
    /// @param amount amount the investor wants to deposit
    function deposit(uint256 amount) external override whenNotPaused {
        if (block.timestamp > endTime) revert AboveMax(endTime, block.timestamp);

        IHasSeedable seedable = IHasSeedable(factory);
        if(isSeedsFarm == true && IDeFarmSeeds(seedable.deFarmSeeds()).balanceOf(msg.sender, manager) == 0) revert ZeroSeedBalance();

        IDepositConfig depositConfig = IDepositConfig(factory);
        if (amount <  depositConfig.minInvestmentAmount()) revert BelowMin(depositConfig.minInvestmentAmount(), amount);
        if (userAmount[msg.sender] + amount > depositConfig.maxInvestmentAmount()) {
            revert AboveMax(depositConfig.maxInvestmentAmount(), userAmount[msg.sender] + amount);
        }
        if (status != SfStatus.NOT_OPENED) revert AlreadyOpened();
        if (totalRaised + amount > depositConfig.capacityPerFarm()) revert AboveMax(depositConfig.capacityPerFarm(), totalRaised + amount);

        IERC20Upgradeable(USDC).transferFrom(msg.sender, address(this), amount);

        totalRaised += amount;
        userAmount[msg.sender] += amount;
        actualTotalRaised += amount;

        emit Deposited(msg.sender, amount);
    }

    /// @notice allows the manager to end the `fundraisingPeriod` early and open a market position
    /// @dev transfers the `totalRaised` usdc of the farm to the operator
    function closeFundraisingAndOpenPosition(bytes memory info) external openOnce whenNotPaused {
        if(msg.sender != manager) revert NoAccess(manager, msg.sender);

        if (status != SfStatus.NOT_OPENED) revert AlreadyOpened();
        // if (block.timestamp < endTime) revert CantClose();
        if (totalRaised < 1) revert ZeroAmount();

        // update state variables
        status = SfStatus.OPENED;
        endTime = block.timestamp;

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);

        IHasProtocolInfo protocolInfo = IHasProtocolInfo(factory);
        (uint256 _protocolFeeNumerator, uint256 _protocolFeeDenominator) = protocolInfo.getProtocolFee();
        uint256 _protocolFee = (totalRaised * _protocolFeeNumerator) / _protocolFeeDenominator;

        if(_protocolFee > 0) {
            totalRaised -= _protocolFee;
            usdc.transfer(protocolInfo.treasury(), _protocolFee);
        }

        if(operator == address(0)) revert ZeroAddress();
        // usdc.transfer(operator, totalRaised);
        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address dex, bytes memory instruction) = dexHandler.depositInstruction(USDC, totalRaised);
        // Collect dex fee
        // totalRaised -= 2e6;
        usdc.approve(dex, totalRaised);
        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();

        emit FundraisingClosedAndPositionOpened(info);
    }

    /// @notice allows the manager to close the fundraising and open a position later
    /// @dev changes the `endTime` to the current `block.timestamp`
    function closeFundraising() external override whenNotPaused {
        if (manager != msg.sender) revert NoAccess(manager, msg.sender);
        if (status != SfStatus.NOT_OPENED) revert AlreadyOpened();
        if (totalRaised < 1) revert ZeroAmount();
        // if (block.timestamp < endTime) revert CantClose();

        endTime = block.timestamp;

        emit FundraisingClosed();
    }

    function openPosition(bytes memory info) external override openOnce whenNotPaused {
        if(msg.sender != manager) revert NoAccess(manager, msg.sender);

        if (endTime > block.timestamp) revert StillFundraising(endTime, block.timestamp);
        if (status != SfStatus.NOT_OPENED) revert AlreadyOpened();
        if (totalRaised < 1) revert ZeroAmount();

        status = SfStatus.OPENED;

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);

        IHasProtocolInfo protocolInfo = IHasProtocolInfo(factory);
        (uint256 _protocolFeeNumerator, uint256 _protocolFeeDenominator) = protocolInfo.getProtocolFee();
        uint256 _protocolFee = (totalRaised * _protocolFeeNumerator) / _protocolFeeDenominator;

        if(_protocolFee > 0) {
            totalRaised -= _protocolFee;
            usdc.transfer(protocolInfo.treasury(), _protocolFee);
        }

        if(operator == address(0)) revert ZeroAddress();

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address dex, bytes memory instruction) = dexHandler.depositInstruction(USDC, totalRaised);
        // Collect dex fee
        // totalRaised -= 2000000;
        usdc.approve(dex, totalRaised);

        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();

        emit PositionOpened(info);
    }

    function setLinkSigner() public whenNotPaused {
        if (isLinkSigner) revert HasLinkSigner();
        if(msg.sender != operator) revert NoAccess(operator, msg.sender);

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address dex,  bytes memory instruction) = dexHandler.linkSignerInstruction(address(this), operator);

        (address feeToken, uint256 feeAmount) = dexHandler.getPaymentFee();
        if (feeToken != USDC) revert InvalidToken(feeToken);
        if (feeAmount > maxFeePay) revert InvalidFee(feeAmount);

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        usdc.approve(dex, feeAmount);

        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();
    }

    /// @notice allows the manager/operator to mark farm as closed
    /// @dev can be called only if theres a position already open
    /// @dev `status` will be `PositionClosed`
    function closePosition(uint256 balance) external override whenNotPaused {
        if (msg.sender != manager && msg.sender != IHasAdministrable(factory).admin()) revert NoAccess(manager, msg.sender);
        if (status != SfStatus.OPENED) revert NoOpenPositions();

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address dex, bytes memory instruction) = dexHandler.withdrawInstruction(address(this), USDC, balance);

        (address feeToken, uint256 feeAmount) = dexHandler.getPaymentFee();
        if (feeToken != USDC) revert InvalidToken(feeToken);
        if (feeAmount > maxFeePay) revert InvalidFee(feeAmount);

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        usdc.approve(dex, feeAmount);

        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();

        if(balance > totalRaised) {
            uint256 profits = balance - totalRaised;

            uint256 _managerFee = (profits * managerFeeNumerator) / FEE_DENOMINATOR;
            if(_managerFee > 0) usdc.transfer(manager, _managerFee);

            remainingAmountAfterClose = balance - _managerFee;
        }
        else {
            remainingAmountAfterClose = balance;
        }

        status = SfStatus.CLOSED;

        emit PositionClosed();
    }

    /// @notice the manager can cancel the farm if they want, after fundraising
    /// @dev can be called by the `manager`
    function cancelByManager() external override whenNotPaused {
        if (msg.sender != manager) revert NoAccess(manager, msg.sender);
        if (status != SfStatus.NOT_OPENED) revert OpenPosition();
        if (block.timestamp > endTime + fundDeadline) revert CantClose();

        fundDeadline = 0;
        endTime = 0;
        status = SfStatus.CANCELLED;

        emit Cancelled();
    }

    function setSeedsFarm(bool enable) external onlyOwner {
        isSeedsFarm = enable;
        emit SeedsFarmChanged(enable);
    }

    /// @notice set the `fundDeadline` for a particular farm to cancel the farm early if needed
    /// @dev can only be called by the `owner` or the `manager` of the farm
    /// @param newFundDeadline new fundDeadline
    function setFundDeadline(uint256 newFundDeadline) external override {
        if (msg.sender != manager && msg.sender != IHasAdministrable(factory).admin()) revert NoAccess(manager, msg.sender);
        if (newFundDeadline > 72 hours) revert AboveMax(72 hours, newFundDeadline);
        fundDeadline = newFundDeadline;
        emit FundDeadlineChanged(newFundDeadline);
    }

    /// @notice transfers the collateral to the investor depending on the investor's weightage to the totalRaised by the farm
    /// @dev will revert if the investor did not invest in the farm during the fundraisingPeriod
    function claim() external override whenNotPaused {
        if (
            status != SfStatus.CLOSED &&
            status != SfStatus.CANCELLED
        ) revert NotFinalised();

        uint256 amount = claimableAmount(msg.sender);
        if (amount < 1) revert ZeroTokenBalance();

        claimed[msg.sender] = true;
        claimAmount[msg.sender] = amount;

        IERC20Upgradeable(USDC).transfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the `status` of a farm in case of an emergency
    /// @param _status new `status` of the farm
    function setStatus(SfStatus _status) external onlyOwner {
        status = _status;
        emit StatusUpdated(msg.sender, _status);
    }

    /// @notice Set the `totalRaised` of a farm in case of an emergency
    /// @param _totalRaised new `totalRaised` of the farm
    function setTotalRaised(uint256 _totalRaised) external onlyOwner {
        totalRaised = _totalRaised;
        emit TotalRaisedUpdated(msg.sender, _totalRaised);
    }

    /// @notice Set the `remainingAmountAfterClose` of a farm in case of an emergency
    /// @param _remainingBalance new `remainingAmountAfterClose` of the farm
    function setRemainingBalance(uint256 _remainingBalance) external onlyOwner {
        remainingAmountAfterClose = _remainingBalance;
        emit RemainingBalanceUpdated(msg.sender, _remainingBalance);
    }

    /// @notice Set the `operator` of an farm in case of an emergency
    /// @param _newOperator new `operator` of the farm
    function setOperator(address _newOperator) external onlyOwner {
        if(_newOperator == address(0)) revert ZeroAddress();
        operator = _newOperator;
        emit OperatorUpdated(msg.sender, operator);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice will change the status of the farm to `LIQUIDATED`
    /// @dev can be called once a farm is liquidated from the dex
    /// @dev can only be called by the `admin`
    function liquidate() external override onlyAdmin whenNotPaused {
        if (status != SfStatus.OPENED) revert NotOpened();
        status = SfStatus.LIQUIDATED;
        emit Liquidated();
    }

    /// @notice will change the status of the farm to `CANCELLED`
    /// @dev can be called if there was nothing raised during `fundraisingPeriod`
    /// @dev or can be called if the manager did not open any position within the `fundDeadline` (default - 72 hours)
    /// @dev can only be called by the `admin`
    function cancelByAdmin() external override onlyAdmin whenNotPaused {
        if (status != SfStatus.NOT_OPENED) revert OpenPosition();
        if (totalRaised == 0) {
            if (block.timestamp <= endTime) revert BelowMin(endTime, block.timestamp);
        } else {
            if (block.timestamp <= endTime + fundDeadline) revert BelowMin(endTime + fundDeadline, block.timestamp);
        }

        status = SfStatus.CANCELLED;

        emit Cancelled();
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW
    //////////////////////////////////////////////////////////////*/

    function getInfo()
        external
        view
        returns (address, uint256, uint256, uint256, uint256, SfStatus)
    {
        return (
            manager,
            totalRaised,
            remainingAmountAfterClose,
            endTime,
            fundDeadline,
            status
        );
    }

    function getManagerFee() public view returns(uint256, uint256) {
        return (managerFeeNumerator, FEE_DENOMINATOR);
    }

    function getStatus() public view returns (SfStatus) {
        return status;
    }

    function getUserAmount(address _investor) public view returns (uint256) {
        return userAmount[_investor];
    }

    /// @notice get the `claimableAmount` of the investor from a particular farm
    /// @dev if theres no position opened, it'll return the deposited amount
    /// @dev after the position is closed, it'll calculate the `claimableAmount` depending on the weightage of the investor
    /// @param _investor address of the investor
    /// @return amount which can be claimed by the investor from a particular farm
    function claimableAmount(address _investor) public view override returns (uint256 amount) {
        if (claimed[_investor] || status == SfStatus.OPENED) {
            amount = 0;
        } else if (status == SfStatus.CANCELLED || status == SfStatus.NOT_OPENED) {
            amount = (totalRaised * userAmount[_investor] * 1e18) / (actualTotalRaised * 1e18);
        } else if (status == SfStatus.CLOSED) {
            amount = (remainingAmountAfterClose * userAmount[_investor] * 1e18) / (actualTotalRaised * 1e18);
        } else {
            amount = 0;
        }
    }

    function getClaimAmount(address _investor) external view override returns (uint256) {
        return claimAmount[_investor];
    }

    function getClaimed(address _investor) external view override returns (bool) {
        return claimed[_investor];
    }

    function withdraw(address receiver, bool isEth, address token, uint256 amount) external onlyOwner returns (bool) {
        if(isEth) {
            payable(receiver).transfer(amount);
        }
        else {
            IERC20Upgradeable(token).transfer(receiver, amount);
        }

        return true;
    }
}