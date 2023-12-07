// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../utils/Constants.sol";
import "../utils/Errors.sol";
import "./Errors.sol";
import "./interfaces/ISingleFarmFactory.sol";
import "./interfaces/IDepositConfig.sol";
import "../interfaces/IHasPausable.sol";
import "../interfaces/IHasAdministrable.sol";
import "../utils/WhitelistedTokens.sol";
import "../utils/Administrable.sol";
import "../utils/Makeable.sol";
import "../utils/ETHFee.sol";
import "../utils/SupportedDex.sol";
import "../utils/ProtocolInfo.sol";
import "../utils/Constants.sol";
import "../utils/OperatorManager.sol";
import "../interfaces/IHasSeedable.sol";
import "../seeds/IDeFarmSeeds.sol";

/// @title SingleFarm Factory
/// @notice Contract for managers create a new instance
/// owner of the contract, used for setting and updating the logic changes
/// admin of the contract, used for updating the particular farms
/// maker of the contract, used for creating new farm instance
/// treasury of the contract, used for receiving fees
contract SingleFarmFactory is
    ISingleFarmFactory,
    IHasPausable,
    IDepositConfig,
    IHasSeedable,
    OwnableUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    WhitelistedTokens,
    IHasAdministrable,
    Administrable,
    Makeable,
    ProtocolInfo,
    ETHFee,
    SupportedDex,
    OperatorManager
{
    using ECDSAUpgradeable for bytes32;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // usdc address
    address public USDC;
    // implementation of the `SingleFarm` contract
    address public singleFarmImplementation;

    // max amount which can be fundraised by the manager per farm
    uint256 public capacityPerFarm;
    // min investment amount per investor per farm
    uint256 public minInvestmentAmount;
    // max investment amount per investor per farm
    uint256 public maxInvestmentAmount;
    // percentage of fees from the profits of the farm to the manager (default - 15e18 (15%))
    uint256 private maxManagerFee;
    // max leverage which can be used by the manager when creating a farm
    uint256 public maxLeverage;
    // min leverage which can be used by the manager when creating a farm
    uint256 public minLeverage;
    // max fundraising period which can be used by the manager to raise funds (defaults - 1 week)
    uint256 public maxFundraisingPeriod;

    address public deFarmSeeds;

    address[] public deployedFarms;
    mapping(address => bool) public isFarm;

    uint public currentOperatorIndex;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    /// @notice initializing state variables in the contructor
    /// @dev require checks to make sure the addresses are not zero addresses
    /// @param _singleFarmImplementation `Single Farm` contract address
    /// @param _capacityPerFarm max amount which can be fundraised by the manager per farm
    /// @param _minInvestmentAmount min investment amount per investor per farm
    /// @param _maxInvestmentAmount max investment amount per investor per farm
    /// @param _maxLeverage max leverage which can be used by the manager when creating an farm
    /// @param _usdc USDC contract address
    function initialize(
        address _dexHandler,
        address _singleFarmImplementation,
        uint256 _capacityPerFarm,
        uint256 _minInvestmentAmount,
        uint256 _maxInvestmentAmount,
        uint256 _maxLeverage,
        address _usdc,
        address _deFarmSeeds
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __EIP712_init("SingleFarmFactory", "1");

        __Administrable_init();
        __Makeable_init();
        __ProtocolInfo_init(5e18);
        __ETHFee_init();
        __SupportedDex_init(_dexHandler);
        __OperatorManager_init();

        if (_singleFarmImplementation == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();

        singleFarmImplementation = _singleFarmImplementation;
        capacityPerFarm = _capacityPerFarm;
        minInvestmentAmount = _minInvestmentAmount;
        maxInvestmentAmount = _maxInvestmentAmount;

        minLeverage = 1e6;
        maxLeverage = _maxLeverage;
        USDC = _usdc;
        maxManagerFee = 15e18;
        maxFundraisingPeriod = 1 weeks;
        deFarmSeeds = _deFarmSeeds;

        currentOperatorIndex = 0;

        emit FarmFactoryInitialized(
            _singleFarmImplementation,
            _capacityPerFarm,
            _minInvestmentAmount,
            _maxInvestmentAmount,
            _maxLeverage,
            ethFee(),
            maxManagerFee,
            FEE_DENOMINATOR,
            _usdc,
            admin(),
            maker(),
            treasury()
        );
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdmin() {
        if (msg.sender != admin()) revert NoAccess(admin(), msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new Single Farm
    /// @dev returns the address of the farm contract with SingleFarm.sol implementation
    /// @param _sf the farm details
    /// @return farm address of the proxy contract which is deployed
    function createFarm(
        Sf calldata _sf,
        uint256 _managerFee
    ) external payable override whenNotPaused returns (address farm) {
        require(numberOperators() > 0, "No operators available");
        address selectedOperator = getOperator(currentOperatorIndex);

        // Move to the next address in a round-robin fashion
        // TODO: don't care about safe math
        currentOperatorIndex = (currentOperatorIndex + 1) % numberOperators();

        // When the manager has initialized seeds before creating a farm
        if(IDeFarmSeeds(deFarmSeeds).balanceOf(msg.sender, msg.sender) == 0) revert ZeroSeedBalance();

        if (msg.value < ethFee()) revert BelowMin(ethFee(), msg.value);
        if (_managerFee > maxManagerFee) revert AboveMax(maxManagerFee, _managerFee);
        if (_sf.fundraisingPeriod < 15 minutes) revert BelowMin(15 minutes, _sf.fundraisingPeriod);
        if (_sf.fundraisingPeriod > maxFundraisingPeriod) {
            revert AboveMax(maxFundraisingPeriod, _sf.fundraisingPeriod);
        }
        if (_sf.leverage < minLeverage) revert BelowMin(minLeverage, _sf.leverage);
        if (_sf.leverage > maxLeverage) revert AboveMax(maxLeverage, _sf.leverage);

        if (!isTokenAllowed(_sf.baseToken)) revert NoBaseToken(_sf.baseToken);

        ERC1967Proxy singleFarm = new ERC1967Proxy(
            ClonesUpgradeable.clone(singleFarmImplementation),
            abi.encodeWithSignature(
                "initialize((address,bool,uint256,uint256,uint256,uint256,uint256),address,uint256,address,address)",
                _sf,
                msg.sender,
                _managerFee,
                USDC,
                selectedOperator
            )
        );

        farm = address(singleFarm);
        deployedFarms.push(farm);
        isFarm[farm] = true;

        emit FarmCreated(
            farm,
            _sf.baseToken,
            _sf.fundraisingPeriod,
            _sf.entryPrice,
            _sf.targetPrice,
            _sf.liquidationPrice,
            _sf.leverage,
            _sf.tradeDirection,
            msg.sender,
            _managerFee,
            FEE_DENOMINATOR,
            selectedOperator,
            block.timestamp
        );
    }

    /*//////////////////////////////////////////////////////////////
                            SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice set the max capacity of collateral which can be raised per farm
    /// @dev can only be called by the `owner`
    /// @param _capacity max capacity of the collateral which can be raised per farm
    function setCapacityPerFarm(uint256 _capacity) external override onlyOwner {
        if (_capacity < 1) revert ZeroAmount();
        capacityPerFarm = _capacity;
        emit CapacityPerFarmChanged(_capacity);
    }

    /// @notice set the min investment of collateral an investor can invest per farm
    /// @dev can only be called by the `owner`
    /// @param _amount min investment of collateral an investor can invest per farm
    function setMinInvestmentAmount(
        uint256 _amount
    ) external override onlyOwner {
        if (_amount < 1) revert ZeroAmount();
        minInvestmentAmount = _amount;
        emit MinInvestmentAmountChanged(_amount);
    }

    /// @notice set the max investment of collateral an investor can invest per farm
    /// @dev can only be called by the `owner`
    /// @param _amount max investment of collateral an investor can invest per farm
    function setMaxInvestmentAmount(
        uint256 _amount
    ) external override onlyOwner {
        if (_amount <= minInvestmentAmount)
            revert BelowMin(minInvestmentAmount, _amount);
        maxInvestmentAmount = _amount;
        emit MaxInvestmentAmountChanged(_amount);
    }

    /// @notice set the max leverage a manager can use when creating an farm
    /// @dev can only be called by the `owner`
    /// @param _maxLeverage max leverage a manager can use when creating an farm
    function setMaxLeverage(uint256 _maxLeverage) external override onlyOwner {
        if (_maxLeverage <= 1e6) revert AboveMax(1e6, _maxLeverage);
        maxLeverage = _maxLeverage;
        emit MaxLeverageChanged(_maxLeverage);
    }

    function setMinLeverage(uint256 _minLeverage) external override onlyOwner {
        if (_minLeverage < 1e6) revert BelowMin(1e6, _minLeverage);
        minLeverage = _minLeverage;
        emit MinLeverageChanged(_minLeverage);
    }

    /// @notice set the max fundraising period a manager can use when creating a farm
    /// @dev can only be called by the `owner`
    /// @param _maxFundraisingPeriod max fundraising period a manager can use when creating a farm
    function setMaxFundraisingPeriod(
        uint256 _maxFundraisingPeriod
    ) external onlyOwner {
        if (_maxFundraisingPeriod < 15 minutes)
            revert BelowMin(15 minutes, _maxFundraisingPeriod);
        maxFundraisingPeriod = _maxFundraisingPeriod;
        emit MaxFundraisingPeriodChanged(_maxFundraisingPeriod);
    }

    /// @notice set the manager fee percent to calculate the manager fees on profits depending on the governance
    /// @dev can only be called by the `owner`
    /// @param newMaxManagerFee the percent which is used to calculate the manager fees on profits
    function setMaxManagerFee(
        uint256 newMaxManagerFee
    ) external override onlyOwner {
        if (newMaxManagerFee > FEE_DENOMINATOR)
            revert AboveMax(FEE_DENOMINATOR, newMaxManagerFee);
        maxManagerFee = newMaxManagerFee;
        emit MaxManagerFeeChanged(newMaxManagerFee);
    }

    /// @notice set the new farm implementation contract address for creating farms
    /// @dev can only be called by the `owner`
    /// @param sf the new farm implementation contract address for creating farms
    function setSfImplementation(address sf) external override onlyOwner {
        singleFarmImplementation = sf;
        emit FarmImplementationChanged(sf);
    }

    /// @notice set the usdc address
    /// @dev can only be called by the `owner`
    /// @param _usdc the usdc address
    function setUsdc(address _usdc) external onlyOwner {
        if (_usdc == address(0)) revert ZeroAddress();
        USDC = _usdc;
        emit UsdcAddressChanged(_usdc);
    }

    function setDeFarmSeeds(address _deFarmSeeds) external onlyOwner {
        deFarmSeeds = _deFarmSeeds;
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer `Eth` or token from this contract to the `receiver` in case of emergency
    /// @dev Can be called only by the `owner`
    /// @param receiver address of the `receiver`
    function withdraw(
        address receiver,
        bool isEth,
        address token,
        uint256 amount
    ) external onlyAdmin returns (bool) {
        if (isEth) {
            payable(receiver).transfer(amount);
        } else {
            IERC20Upgradeable(token).transfer(receiver, amount);
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW
    //////////////////////////////////////////////////////////////*/
    function getMaxManagerFee() public view returns (uint256, uint256) {
        return (maxManagerFee, FEE_DENOMINATOR);
    }

    function getCreateFarmDigest(
        address _operator,
        address _manager
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(CREATE_FARM_HASH, _operator, _manager))
            );
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSE/UNPAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause contract
    /// @dev can only be called by the `owner` when the contract is not paused
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    /// @dev can only be called by the `owner` when the contract is paused
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    /// @notice Return the pause status
    /// @return The pause status
    function isPaused() external view override returns (bool) {
        return paused();
    }
}
