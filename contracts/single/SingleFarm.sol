// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "../utils/Constants.sol";
import "../utils/Errors.sol";
import "./Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISingleFarm} from "./interfaces/ISingleFarm.sol";
import {ISingleFarmFactory} from "./interfaces/ISingleFarmFactory.sol";
import {IDepositConfig} from "./interfaces/IDepositConfig.sol";
import {IHasAdministrable} from "../interfaces/IHasAdministrable.sol";
import "../interfaces/IHasOwnable.sol";
import "../interfaces/IHasPausable.sol";
import "../interfaces/IHasProtocolInfo.sol";
import "../interfaces/ISupportedDex.sol";
import "../interfaces/IHasSeedable.sol";
import "../interfaces/IDeFarmSeeds.sol";
import "../utils/BlastYield.sol";
import "../interfaces/thruster/IThrusterRouter02.sol";

/// @title SingleFarm
/// @notice Contract for the investors to deposit and for managers to open and close positions
contract SingleFarm is ISingleFarm, Initializable, BlastYield {
    bool private calledOpen;

    ISingleFarmFactory.Sf public sf;

    address public USDC;

    address public factory;
    address public manager; // Farm manager
    uint256 public endTime;
    uint256 public fundDeadline;
    uint256 public totalRaised;
    uint256 public actualTotalRaised;
    SfStatus public status;
    uint256 public override remainingAmountAfterClose;
    uint256 public managerFeeReceived;
    mapping(address => uint256) public userAmount;
    mapping(address => uint256) public claimAmount;
    mapping(address => bool) public claimed;
    uint256 private managerFeeNumerator;
    bool fundraisingClosed;
    uint256 public maxFeePay;
    bool public isPrivate;

    function initialize(
        ISingleFarmFactory.Sf calldata _sf,
        address _manager,
        uint256 _managerFee,
        address _usdc,
        bool _isPrivate
    ) public initializer {
        sf = _sf;
        factory = msg.sender;
        manager = _manager;
        managerFeeNumerator = _managerFee;
        endTime = block.timestamp + _sf.fundraisingPeriod;
        fundDeadline = 72 hours;
        USDC = _usdc;
        maxFeePay = 10*(10**IERC20MetadataUpgradeable(_usdc).decimals());
        status = SfStatus.NOT_OPENED;
        fundraisingClosed = false;
        managerFeeReceived = 0;
        isPrivate = _isPrivate;

        __BlastYield_init(IHasOwnable(factory).owner());
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
        if (status != SfStatus.NOT_OPENED) revert AlreadyOpened();

        if (isPrivate) {
            IHasSeedable seedable = IHasSeedable(factory);
            if(IDeFarmSeeds(seedable.deFarmSeeds()).balanceOf(msg.sender, manager) == 0) revert ZeroSeedBalance(manager);
        }

        IDepositConfig depositConfig = IDepositConfig(factory);
        if (amount <  depositConfig.minInvestmentAmount()) revert BelowMin(depositConfig.minInvestmentAmount(), amount);
        if (userAmount[msg.sender] + amount > depositConfig.maxInvestmentAmount()) {
            revert AboveMax(depositConfig.maxInvestmentAmount(), userAmount[msg.sender] + amount);
        }
        if (totalRaised + amount > depositConfig.capacityPerFarm()) revert AboveMax(depositConfig.capacityPerFarm(), totalRaised + amount);

        IERC20Upgradeable(USDC).transferFrom(msg.sender, address(this), amount);

        totalRaised += amount;
        userAmount[msg.sender] += amount;
        actualTotalRaised += amount;

        emit Deposited(msg.sender, amount);
    }

    /// @notice allows the manager to close the fundraising and open a position later
    /// @dev changes the `endTime` to the current `block.timestamp`
    function closeFundraising() external override whenNotPaused {
        if (manager != msg.sender) revert NoAccess(manager, msg.sender);
        if (fundraisingClosed) revert HasClosedFundraising();
        if (status != SfStatus.NOT_OPENED) revert AlreadyOpened();
        if (totalRaised < 1) revert ZeroAmount();

        endTime = block.timestamp;
        fundraisingClosed = true;

        emit FundraisingClosed(totalRaised);
    }

    function openPosition(uint256 amountBaseTokenMin) external override openOnce whenNotPaused {
        if(msg.sender != manager) revert NoAccess(manager, msg.sender);

        if (!fundraisingClosed) revert StillFundraising(endTime, block.timestamp);
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

        // Swap here
        ISupportedDex supportedDex = ISupportedDex(factory);
        address router = supportedDex.dexRouter();

        require(usdc.approve(router, totalRaised), 'approve failed.');
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = sf.baseToken;
        IThrusterRouter02 thrusterRouter = IThrusterRouter02(router);
        uint256[] memory amounts = thrusterRouter.swapExactTokensForTokens(
            totalRaised,
            amountBaseTokenMin,
            path,
            address(this),
            block.timestamp
        );

        if(amounts[1] < 1) revert ZeroAmount();

        emit PositionOpened(amounts[0], amounts[1]);
    }

    /// @notice allows the manager/operator to mark farm as closed
    /// @dev can be called only if theres a position already open
    /// @dev `status` will be `PositionClosed`
    function closePosition() external override whenNotPaused {
        if (msg.sender != manager && msg.sender != IHasAdministrable(factory).admin()) revert NoAccess(manager, msg.sender);
        if (status != SfStatus.OPENED) revert NoOpenPositions();

        // Swap here
        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        IERC20Upgradeable baseToken = IERC20Upgradeable(sf.baseToken);
        uint256 baseTokenBalance = baseToken.balanceOf(address(this));

        ISupportedDex supportedDex = ISupportedDex(factory);
        address router = supportedDex.dexRouter();

        require(baseToken.approve(router, baseTokenBalance), 'approve failed.');
        address[] memory path = new address[](2);
        path[0] = sf.baseToken;
        path[1] = USDC;
        IThrusterRouter02 thrusterRouter = IThrusterRouter02(router);
        thrusterRouter.swapExactTokensForTokens(
            baseTokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        );

        baseTokenBalance = baseToken.balanceOf(address(this));
        if(baseTokenBalance > 0) revert CantClosePosition();

        // Update balance
        uint256 balance = usdc.balanceOf(address(this));
        if (balance < 1) revert ZeroTokenBalance();

        if(balance > totalRaised) {
            uint256 profits = balance - totalRaised;

            uint256 _managerFee = (profits * managerFeeNumerator) / FEE_DENOMINATOR;
            if(_managerFee > 0) {
                managerFeeReceived += _managerFee;
            }

            remainingAmountAfterClose = balance - _managerFee;
        }
        else {
            remainingAmountAfterClose = balance;
        }

        status = SfStatus.CLOSED;

        emit PositionClosed(balance);
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

    /// @notice set the `fundDeadline` for a particular farm to cancel the farm early if needed
    /// @dev can only be called by the `admin` or the `manager` of the farm
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
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice will change the status of the farm to `LIQUIDATED`
    /// @dev can be called once a farm is liquidated from the dex
    /// @dev can only be called by the `admin`
    function liquidate() external override onlyAdmin whenNotPaused {
        if (status != SfStatus.OPENED) revert NotOpened();

        uint256 balance = getBalance();

        if (balance >= 1) revert NotAbleLiquidate(balance);

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
            amount = (totalRaised * userAmount[_investor]) / actualTotalRaised;
        } else if (status == SfStatus.CLOSED) {
            amount = (remainingAmountAfterClose * userAmount[_investor]) / actualTotalRaised;
        } else {
            amount = 0;
        }
        if (_investor == manager && managerFeeReceived > 0) {
            amount += managerFeeReceived;
        }
    }

    function getClaimAmount(address _investor) external view override returns (uint256) {
        return claimAmount[_investor];
    }

    function getClaimed(address _investor) external view override returns (bool) {
        return claimed[_investor];
    }

    function getBalance() public view returns(uint256) {
        address farm = address(this);

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        uint256 usdcBalance = usdc.balanceOf(farm);

        IERC20Upgradeable baseToken = IERC20Upgradeable(sf.baseToken);
        uint256 baseTokenBalance = baseToken.balanceOf(farm);

        ISupportedDex supportedDex = ISupportedDex(factory);
        IThrusterRouter02 thrusterRouter = IThrusterRouter02(supportedDex.dexRouter());
        address[] memory path = new address[](2);
        path[0] = sf.baseToken;
        path[1] = USDC;

        uint256[] memory amounts = thrusterRouter.getAmountsOut(baseTokenBalance, path);

        return usdcBalance + amounts[1];
    }
}