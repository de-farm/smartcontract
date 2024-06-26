// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
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
import "../interfaces/IDexHandler.sol";
import "../interfaces/IHasSeedable.sol";
import "../interfaces/IDeFarmSeeds.sol";
import "../utils/BlastYield.sol";

/// @title SingleFarm
/// @notice Contract for the investors to deposit and for managers to open and close positions
contract SingleFarm is ISingleFarm, Initializable, EIP712Upgradeable, BlastYield {
    using ECDSAUpgradeable for bytes32;

    bool private calledOpen;

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
    uint256 public managerFeeReceived;
    mapping(address => uint256) public userAmount;
    mapping(address => uint256) public claimAmount;
    mapping(address => bool) public claimed;
    uint256 private managerFeeNumerator;
    bool fundraisingClosed;
    bool isLinkSigner;
    uint256 public maxFeePay;
    uint256 public holdDexFee;
    bool public isPrivate;

    function initialize(
        ISingleFarmFactory.Sf calldata _sf,
        address _manager,
        uint256 _managerFee,
        address _usdc,
        address _operator,
        bool _isPrivate
    ) public initializer {
        sf = _sf;
        factory = msg.sender;
        manager = _manager;
        managerFeeNumerator = _managerFee;
        operator = _operator;
        endTime = block.timestamp + _sf.fundraisingPeriod;
        fundDeadline = 72 hours;
        USDC = _usdc;
        isLinkSigner = false;
        maxFeePay = 10*(10**IERC20MetadataUpgradeable(_usdc).decimals());
        status = SfStatus.NOT_OPENED;
        fundraisingClosed = false;
        holdDexFee = 0;
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

    modifier whenLinkedSigner() {
        require(isLinkSigner, "farm is not linked with a signer");
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

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address feeToken, uint256 feeAmount) = dexHandler.getPaymentFee();
        if (feeToken != USDC) revert InvalidToken(feeToken);
        if (feeAmount > maxFeePay) revert FeeTooHigh(feeAmount);

        // holdDexFee holds fee for setLinkSigner and withdraw
        holdDexFee = feeAmount * 2;

        if (totalRaised <= holdDexFee) revert NotEnoughFund();

        totalRaised -= holdDexFee;

        endTime = block.timestamp;
        fundraisingClosed = true;

        emit FundraisingClosed(totalRaised);
    }

    function openPosition(bytes calldata info) external override openOnce whenNotPaused whenLinkedSigner {
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

        if(operator == address(0)) revert ZeroAddress();

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address dex, bytes memory instruction) = dexHandler.depositInstruction(USDC, totalRaised);
        usdc.approve(dex, totalRaised);

        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();

        emit PositionOpened(info);
    }

    function setLinkSigner() public whenNotPaused {
        if (isLinkSigner) revert HasLinkSigner();
        require(msg.sender == operator || msg.sender == IHasOwnable(factory).owner()
        || msg.sender == IHasAdministrable(factory).admin(), "no access");

        // Ensure farm is end fundraising
        if (!fundraisingClosed) revert StillFundraising(endTime, block.timestamp);

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        (address dex,  bytes memory instruction) = dexHandler.linkSignerInstruction(address(this), operator);

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        usdc.approve(dex, holdDexFee);

        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();
        isLinkSigner = true;

        emit LinkedSigner(address(this), operator);
    }

    /// @notice allows the manager/operator to mark farm as closed
    /// @dev can be called only if theres a position already open
    /// @dev `status` will be `PositionClosed`
    function closePosition(bytes calldata _signature) external override whenNotPaused whenLinkedSigner {
        if (msg.sender != manager && msg.sender != IHasAdministrable(factory).admin()) revert NoAccess(manager, msg.sender);
        if (status != SfStatus.OPENED) revert NoOpenPositions();

        // Verifying the correctness of the signature. Ensure position has closed on dex.
        if(getClosePositionDigest(address(this))
            .toEthSignedMessageHash().recover(_signature) != operator) revert InvalidSignature(operator);

        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        uint256 balance = dexHandler.getBalance(address(this), USDC);
        if (balance < 1) revert ZeroTokenBalance();

        (address dex, bytes memory instruction) = dexHandler.withdrawInstruction(address(this), USDC, balance);

        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        usdc.approve(dex, holdDexFee);

        (bool success, ) = dex.call(instruction);
        if(!success) revert ExecutionCallFailure();

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

    /// @notice Set the `operator` of an farm in case of an emergency
    /// @param _newOperator new `operator` of the farm
    function setOperator(address _newOperator) external onlyOwner {
        if(_newOperator == address(0)) revert ZeroAddress();
        if (_newOperator == operator) {
            return;
        }
        operator = _newOperator;
        isLinkSigner = false;
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
        ISupportedDex supportedDex = ISupportedDex(factory);
        IDexHandler dexHandler = IDexHandler(supportedDex.dexHandler());

        uint256 balance = dexHandler.getBalance(address(this), USDC);
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

    function getClosePositionDigest(
        address _farm
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CLOSE_POSITION_HASH,
                        _farm
                    )
                )
            );
    }

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
}