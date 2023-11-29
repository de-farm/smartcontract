// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IVerifier.sol";
import "./interfaces/ISeasonalFarm.sol";
import "../interfaces/IHasOwnable.sol";
import "../interfaces/IHasPausable.sol";
import "./interfaces/IManaged.sol";
import "./interfaces/IFarmManagement.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasFeeInfo.sol";

import "../interfaces/IHasAdministrable.sol";
import "../interfaces/IHasETHFee.sol";
import "../interfaces/IHasProtocolInfo.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "../utils/Errors.sol";
import "./Errors.sol";

uint256 constant DEFAULT_PRICE = 1e18;
uint256 constant DUST_FEE = 1e6;

contract SeasonalFarm is
    ISeasonalFarm, ERC20Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMathUpgradeable for uint256;

    // All events must be accompanied by the farm address
    event FarmManagementSet(
        address farm,
        address farmManagement,
        address from
    );

    event Deposited(
        address farm,
        address investor,
        address assetDeposited,
        uint256 amountDeposited,
        uint256 valueDeposited,
        uint256 tokensReceived
    );

    event Withdrawal(
        address farm,
        address investor,
        address withdrawnAsset,
        uint256 tokensWithdrawn,
        uint256 portion,
        uint256 valueWithdrawn
    );

    event Invested(
        address farm,
        address manager,
        address asset,
        uint256 amount,
        bytes info
    );

    event Divested(
        address farm,
        address manager,
        address asset,
        uint256 amount,
        bytes info,
        bytes signature
    );

    event Liquidated(
        address farm,
        address manager,
        uint256 order
    );

    event MinDepositChanged(address farm, uint256 minDeposit);
    event MaxDepositChanged(address farm, uint256 maxDeposit);

    event EntranceFeeMinted(
        address farm,
        address investor,
        address manager,
        uint256 available,
        uint256 managerFee,
        uint256 adminFee
    );

    event ExitFeeMinted(
        address farm,
        address investor,
        address manager,
        uint256 available,
        uint256 managerFee,
        uint256 adminFee
    );

    event PenaltyFeeMinted(
        address farm,
        address investor,
        uint256 fee
    );

    event ManagementFeeMinted(
        address farm,
        address manager,
        uint256 available,
        uint256 managerFee,
        uint256 adminFee,
        uint256 latestManagementFeeMintAt
    );

    event PerformanceFeeMinted(
        address farm,
        address manager,
        uint256 available,
        uint256 managerFee,
        uint256 adminFee,
        uint256 tokenPriceAtLastFeeMint
    );

    address public override factory;
    address public override farmManagement;
    address public operator;

    bool public isPrivate;
    uint256 public startTime;
    uint256 public override endTime; // If this value is zero, it indicates that the farm is unlimited.
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public initialLockupPeriod;

    uint256 public tokenPriceAtLastPerformanceFeeMint;
    uint256 public latestManagementFeeMintAt;

    mapping(bytes => bool) public divests;

    function initialize(
        ISeasonalFarm.FarmInfo calldata _info,
        address _operator
    ) public initializer {
        __ERC20_init(_info.name, _info.symbol);
        __ReentrancyGuard_init();

        factory = msg.sender;
        operator = _operator;

        isPrivate = _info.isPrivate;

        startTime = block.timestamp;

        if(_info.farmingPeriod > 0) {
            endTime = startTime + _info.farmingPeriod;
        }
        else {
            endTime = 0;
        }

        minDeposit = _info.minDeposit;
        maxDeposit = _info.maxDeposit;

        initialLockupPeriod = _info.initialLockupPeriod;

        tokenPriceAtLastPerformanceFeeMint = DEFAULT_PRICE; // default value: $1
        latestManagementFeeMintAt = block.timestamp;
    }

    function setFarmManagement(address _farmManagement) external override returns (bool) {
        require(_farmManagement != address(0), "Invalid Farm Management address");
        require(
            msg.sender == address(factory) || msg.sender == IHasOwnable(factory).owner(),
            "only factory or owner allowed"
        );

        farmManagement = _farmManagement;

        emit FarmManagementSet(address(this), _farmManagement, msg.sender);

        return true;
    }

    function setMinDeposit(uint256 _amount) external onlyManager {
        if (_amount < 1) revert ZeroAmount();
        minDeposit = _amount;
        emit MinDepositChanged(address(this), _amount);
    }

    function setMaxDeposit(uint256 _amount) external onlyManager {
        if (_amount <= minDeposit) revert BelowMin(minDeposit, _amount);
        maxDeposit = _amount;
        emit MaxDepositChanged(address(this), _amount);
    }

    /// MODIFIERS ///
    modifier onlyPrivate() {
        require(
            !isPrivate ||
            msg.sender == manager() ||
            isMemberAllowed(msg.sender),
            "only members allowed"
        );
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager(), "only manager");
        _;
    }

    modifier whenNotPaused() {
        require(!IHasPausable(factory).isPaused(), "contracts paused");
        _;
    }

    function manager() internal view returns (address) {
        return IManaged(farmManagement).manager();
    }

    function isMemberAllowed(address member) public view returns (bool) {
        return IManaged(farmManagement).isMemberAllowed(member);
    }

    function tryDeposit(address _asset, uint256 _amount) public view returns (uint256 shares) {

    }

    function deposit(address _asset, uint256 _amount, uint256 slippage)
        external onlyPrivate whenNotPaused
        returns (uint256)
    {
        if(_asset == address(0)) revert ZeroAddress();
        if(_amount == 0) revert ZeroAmount();
        if (block.timestamp > endTime) revert AboveMax(endTime, block.timestamp);

        // asset address must be in the deposit list
        IFarmManagement farmManagementContract = IFarmManagement(farmManagement);
        if(!farmManagementContract.isDepositAsset(_asset)) revert InvalidAddress(_asset);

        // Calculate asset value in usd
        uint256 usdAmount = IHasAssetInfo(factory).assetValue(_asset, _amount);

        // checking for min/max value of asset
        if(usdAmount < minDeposit) revert BelowMin(minDeposit, usdAmount);
        if(usdAmount > maxDeposit) revert AboveMax(maxDeposit, usdAmount);

        // Calc the asset value before transfer asset into this farm
        uint256 totalSupplyBefore = totalSupply();
        uint256 fundValue = farmManagementContract.totalFundValue();

        require(IERC20Upgradeable(_asset).transferFrom(msg.sender, address(this), _amount), "token transfer failed");

        uint256 liquidityMinted;
        if (totalSupplyBefore > 0) {
            liquidityMinted = usdAmount.mul(totalSupplyBefore).div(fundValue);
        } else {
            liquidityMinted = usdAmount;
        }

        // Entrance fee
        (uint256 entranceFeeNumerator, uint256 entranceFeeDenominator) = farmManagementContract.getEntranceFee();
        uint256 entranceFee = liquidityMinted.mul(entranceFeeNumerator).div(entranceFeeDenominator);
        if(entranceFee > 0) {
            liquidityMinted = liquidityMinted.sub(entranceFee);

            address to = manager();
            (uint256 managerFee, uint256 adminFee) = _mintFeeToManager(to, entranceFee);
            emit EntranceFeeMinted(address(this), msg.sender, to, entranceFee, managerFee, adminFee);
        }

        // Slippage
        if(liquidityMinted < slippage) revert SlippageIssue();

        _mint(msg.sender, liquidityMinted);

        emit Deposited(address(this), msg.sender, _asset, _amount, usdAmount, liquidityMinted);

        return liquidityMinted;
    }

    function withdraw(address _asset, uint256 _shareAmount, uint256 _slippage)
        external whenNotPaused nonReentrant
    {
        require(IHasSupportedAsset(farmManagement).isSupportedAsset(_asset), "asset is not supported");
        require(balanceOf(msg.sender) >= _shareAmount, "insufficient balance");

        IFarmManagement farmManagementContract = IFarmManagement(farmManagement);
        // Exit fee
        (uint256 exitFeeNumerator, uint256 exitFeeDenominator) = farmManagementContract.getExitFee();
        uint256 exitFee = _shareAmount.mul(exitFeeNumerator).div(exitFeeDenominator);
        if(exitFee > 0) {
            // remaining = remaining.sub(exitFee);
            address to = manager();
            (uint256 managerFee, uint256 adminFee) = _mintFeeToManager(to, exitFee);
            emit ExitFeeMinted(address(this), msg.sender, to, exitFee, managerFee, adminFee);

            // Penalty fee
            uint256 _penaltyFee = _availablePenaltyFee(exitFee);
            if(_penaltyFee > 0) {
                IHasProtocolInfo protocolInfo = IHasProtocolInfo(factory);
                _mint(protocolInfo.treasury(), _penaltyFee);
                emit PenaltyFeeMinted(address(this), msg.sender, _penaltyFee);
                // _shareAmount = _shareAmount.sub(_penaltyFee);
            }
        }

        // calculate the proportion of the shares
        uint256 portion = _shareAmount.mul(10**18).div(totalSupply());
        uint256 fundValue = farmManagementContract.totalFundValue();
        uint256 valueInDollar = portion*fundValue/(10**18);

        _burn(msg.sender, _shareAmount);

        // Convert the value to asset amount
        uint256 assetAmount = IHasAssetInfo(factory).convertValueToAsset(_asset, valueInDollar);

        if(assetAmount < _slippage) revert SlippageIssue();

        IERC20Upgradeable assetContract = IERC20Upgradeable(_asset);

        // Check if the asset amount is less than the balance
        if(assetContract.balanceOf(address(this)) < assetAmount) revert NotEnoughBalance();
        // transfer the asset
        assetContract.transfer(msg.sender, assetAmount);

        emit Withdrawal(address(this), msg.sender, _asset, _shareAmount, portion, assetAmount);
    }

    /// @notice transfer asset to the operator
    function invest(address _asset, uint256 _amount, bytes memory _info)
        external payable onlyManager whenNotPaused nonReentrant
    {
        uint256 ethFee = IHasETHFee(factory).ethFee();
        if (msg.value < ethFee) revert BelowMin(ethFee, msg.value);
        payable(operator).transfer(ethFee);

        require(IHasSupportedAsset(farmManagement).isSupportedAsset(_asset), "asset is not supported");

        if(operator == address(0)) revert ZeroAddress();
        IERC20Upgradeable(_asset).transfer(operator, _amount);

        emit Invested(address(this), msg.sender, _asset, _amount, _info);
    }

    function divest(address _asset, bytes memory _info, bytes memory _signature)
        external onlyManager whenNotPaused nonReentrant
    {
        if(divests[_signature]) revert AlreadyDivested(_signature);
        divests[_signature] = true;

        address farm = address(this);
        // Verifying the correctness of the signature
        IVerifier verifier = IVerifier(factory);
        bytes32 digest = verifier.getDivestDigest(farm, _asset, _info);
        if(verifier.recoverSigner(_signature, digest) != operator) revert InvalidSignature(operator);

        IERC20Upgradeable assetContract = IERC20Upgradeable(_asset);
        uint256 allowanceAmount = assetContract.allowance(operator, address(this));
        if(allowanceAmount == 0) revert ZeroAmount();
        assetContract.transferFrom(operator, farm, allowanceAmount);

        emit Divested(farm, msg.sender, _asset, allowanceAmount, _info, _signature);
    }

    function liquidate()
        external whenNotPaused nonReentrant
    {
        address admin = IHasAdministrable(factory).admin();
        if(msg.sender != manager() &&  msg.sender != admin) revert NoAccess(admin, msg.sender);
    }


    function mintManagementFee() external whenNotPaused {
        uint256 time_interval = block.timestamp - latestManagementFeeMintAt;
        if(time_interval > 0) {
            (uint256 managementFeeNumerator, uint256 managementFeeDenomirator) = IFarmManagement(farmManagement).getManagementFee();
            uint256 tokenSupply = totalSupply();
            uint256 _available = tokenSupply.mul(time_interval)
                .mul(managementFeeNumerator).div(managementFeeDenomirator).div(365 days);

            // Ignore dust when minting fees
            if(_available >= DUST_FEE) {
                address to = manager();
                (uint256 managerFee, uint256 adminFee) = _mintFeeToManager(to, _available);
                latestManagementFeeMintAt = block.timestamp;

                emit ManagementFeeMinted(
                    address(this),
                    to,
                    _available,
                    managerFee,
                    adminFee,
                    latestManagementFeeMintAt
                );
            }
        }
    }

    function mintPerformanceFee() external whenNotPaused {
        IFarmManagement farmManagementContract = IFarmManagement(farmManagement);

        uint256 _fundValue = farmManagementContract.totalFundValue();
        uint256 _tokenSupply = totalSupply();
        (uint256 performanceFeeNumerator, uint256 performanceFeeDenominator) = farmManagementContract.getPerformanceFee();

        uint256 _available = _availablePerformanceFee(
            _fundValue,
            _tokenSupply,
            tokenPriceAtLastPerformanceFeeMint,
            performanceFeeNumerator,
            performanceFeeDenominator
        );

        if(_available >= DUST_FEE) {
            address to = manager();
            (uint256 managerFee, uint256 adminFee) = _mintFeeToManager(to,  _available);

            tokenPriceAtLastPerformanceFeeMint = _calSharePrice(_fundValue, _tokenSupply);

            emit PerformanceFeeMinted(
                address(this),
                to,
                _available,
                managerFee,
                adminFee,
                tokenPriceAtLastPerformanceFeeMint
            );
        }
    }

    function _availablePerformanceFee(
        uint256 _fundValue,
        uint256 _tokenSupply,
        uint256 _lastFeeMintPrice,
        uint256 _feeNumerator,
        uint256 _feeDenominator
    ) internal pure returns (uint256) {
        if (_tokenSupply == 0 || _fundValue == 0) return 0;

        uint256 currentTokenPrice = _fundValue.mul(10**18).div(_tokenSupply);

        if (currentTokenPrice <= _lastFeeMintPrice) return 0;

        uint256 available = currentTokenPrice
            .sub(_lastFeeMintPrice)
            .mul(_tokenSupply)
            .mul(_feeNumerator)
            .div(_feeDenominator)
            .div(currentTokenPrice);

        return available;
    }

    function _availablePenaltyFee(uint256 exitFee) internal view returns (uint256 penaltyFee) {
        uint256 duration = block.timestamp - startTime;
        if(duration >= 0 && duration < initialLockupPeriod) {
            uint256 penaltyFeeNumerator = 0;
            uint256 penaltyFeeDenomirator = 0;
            if(duration < initialLockupPeriod/3) {
                (penaltyFeeNumerator, penaltyFeeDenomirator) = IHasFeeInfo(factory).getPenaltyFee(0);
            }
            else if(duration < initialLockupPeriod*2/3) {
                (penaltyFeeNumerator, penaltyFeeDenomirator) = IHasFeeInfo(factory).getPenaltyFee(1);
            }
            else if(duration < initialLockupPeriod) {
                (penaltyFeeNumerator, penaltyFeeDenomirator) = IHasFeeInfo(factory).getPenaltyFee(2);
            }

            if(penaltyFeeNumerator > 0) {
                penaltyFee = exitFee.mul(penaltyFeeNumerator).div(penaltyFeeDenomirator);
            }
        }
    }

    function _mintFeeToManager(address to, uint256 _fee) internal returns (uint256 managerFee, uint256 adminFee) {
        IHasProtocolInfo protocolInfo = IHasProtocolInfo(factory);

        (uint256 adminFeeNumerator, uint256 adminFeeDenominator) = protocolInfo.getProtocolFee();
        adminFee = _fee.mul(adminFeeNumerator).div(adminFeeDenominator);
        managerFee = _fee.sub(adminFee);

        if(adminFee > 0) _mint(protocolInfo.treasury(), adminFee);
        if(managerFee > 0) _mint(to, managerFee);
    }

    function _transferFeeToManager(address from, address to, uint256 fee) internal returns (uint256 managerFee, uint256 adminFee) {
        IHasProtocolInfo protocolInfo = IHasProtocolInfo(factory);

        (uint256 adminFeeNumerator, uint256 adminFeeDenominator) = protocolInfo.getProtocolFee();
        adminFee = fee.mul(adminFeeNumerator).div(adminFeeDenominator);
        managerFee = fee.sub(adminFee);

        if(adminFee > 0) require(transferFrom(from, protocolInfo.treasury(), adminFee), "token transfer failed");
        if(managerFee > 0) require(transferFrom(from, to, fee), "token transfer failed");
    }

    function assetValueToShares(uint256 assetValue, uint256 sharePrice) public view returns(uint256) {
        return assetValue.mul(10**decimals()).div(sharePrice);
    }

    function getSharePrice() public view returns(uint256) {
        return _calSharePrice(IFarmManagement(farmManagement).totalFundValue(), totalSupply());
    }

    function _calSharePrice(uint256 _fundValue, uint256 _tokenSupply) internal pure returns (uint256) {
        if (_tokenSupply == 0 || _fundValue == 0) return DEFAULT_PRICE;

        return _fundValue.mul(10**18).div(_tokenSupply);
    }
}