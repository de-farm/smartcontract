// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { WhitelistedTokens } from "../utils/WhitelistedTokens.sol";

import "./interfaces/IHasFeeInfo.sol";
import "../interfaces/IHasPausable.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IAssetHandler.sol";
import "../interfaces/IDexHandler.sol";
import "./interfaces/IVerifier.sol";

import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/ISeasonalFarm.sol";
import "./interfaces/IFarmManagement.sol";
import "../utils/Administrable.sol";
import "../utils/Makeable.sol";
import "../interfaces/IHasAdministrable.sol";
import "../utils/Constants.sol";
import "../utils/ProtocolInfo.sol";
import "../utils/ETHFee.sol";
import "../utils/SupportedDex.sol";
import "../utils/Errors.sol";
import "./Errors.sol";

contract SeasonalFarmFactory is
    IHasFeeInfo, IHasAssetInfo, IHasPausable, IVerifier,
    OwnableUpgradeable, PausableUpgradeable, EIP712Upgradeable,
    WhitelistedTokens, IHasAdministrable, Administrable, Makeable, ProtocolInfo,
    ETHFee, SupportedDex
{
    using ECDSAUpgradeable for bytes32;
    using SafeMathUpgradeable for uint256;
    bytes32 constant DIVEST_HASH = keccak256("Divest");

    event FarmFactoryInitialized(
        uint256 ethFee
    );

    event AssetHandlerSet(address assetHandler);

    event MaximumSupportedAssetCountChanged(uint256 count);

    event MaximumManagerFeeChanged(uint256 numerator, uint256 denominator);
    event MaximumPerformanceFeeChanged(uint256 numerator, uint256 denominator);
    event MaximumEntranceFeeChanged(uint256 numerator, uint256 denominator);
    event MaximumExitFeeChanged(uint256 numerator, uint256 denominator);

    event FarmCreated(
        address indexed farm,
        address indexed farmManagement,
        address indexed manager,
        ISeasonalFarm.FarmInfo info,
        IHasFeeInfo.Fees fees,
        uint256 feeDenominator,
        uint256 endTime,
        address operator
    );

    address private seasonalFarmImplementation;
    address private farmManagementImplementation;

    address public assetHandler;

    Fees private maximumFees;
    uint256[] penaltyFees;

    uint256 internal _maximumSupportedAssetCount;

    address[] public deployedFarms;
    mapping(address => bool) public isFarm;

    mapping(address => bool) public operators;

    function initialize(
        address _assetHandler,
        address _dexHandler,
        address[] memory _whitelistedTokens,
        address _seasonalFarmImplementation,
        address _farmManagementImplementation
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __EIP712_init("SeasonalFarmFactory", "1");

        __Administrable_init();
        __Makeable_init();
        __ProtocolInfo_init(FEE_DENOMINATOR.div(10)); // default: 10%
        __ETHFee_init();
        __SupportedDex_init(_dexHandler);
        _setAssetHandler(_assetHandler);

        seasonalFarmImplementation = _seasonalFarmImplementation;
        farmManagementImplementation = _farmManagementImplementation;

        _setMaximumSupportedAssetCount(3);

        _setMaximumManagementFee(FEE_DENOMINATOR*3/100); // default value: 3%
        _setMaximumPerformanceFee(FEE_DENOMINATOR*70/100); // default value: 10%
        _setMaximumEntranceFee(FEE_DENOMINATOR*1/100); // default value: 2%
        _setMaximumExitFee(FEE_DENOMINATOR*1/100); // default value: 2%

        // 10%, 5%, 3%
        penaltyFees = [FEE_DENOMINATOR*10/100, FEE_DENOMINATOR*5/100, FEE_DENOMINATOR*3/100];

        _addTokens(_whitelistedTokens);

        emit FarmFactoryInitialized(
            ethFee()
        );
    }

    /// @notice Function to create a new seasonal farm
    /// @param _manager A manager address
    /// @param _info the farm details
    /// @param _fees The numerator of the manager fee
    /// @return farm Address of the farm
    function createFarm(
        address _manager,
        ISeasonalFarm.FarmInfo calldata _info,
        IHasSupportedAsset.Asset[] memory _supportedAssets,
        Fees memory _fees,
        address _operator,
        bytes memory _signature
    ) external whenNotPaused returns (address) {
        if(operators[_operator]) revert InvalidAddress(_operator);
        operators[_operator] = true;

        // Verifying the correctness of the signature
        if(getCreateFarmDigest(_operator, msg.sender)
            .toEthSignedMessageHash().recover(_signature) != maker()) revert InvalidSignature(maker());

        if(bytes(_info.name).length == 0) revert InvalidValue(_info.name);
        if(bytes(_info.symbol).length == 0) revert InvalidValue(_info.symbol);
        if(_manager == address(0)) revert ZeroAddress();

        if (_info.minDeposit > _info.maxDeposit) revert BelowMin(_info.minDeposit, _info.maxDeposit);
        if (_info.farmingPeriod != 0 && _info.farmingPeriod < 30 days) revert BelowMin(1 hours, _info.farmingPeriod);
        if (_info.initialLockupPeriod >= _info.farmingPeriod) revert AboveMax(_info.farmingPeriod, _info.initialLockupPeriod);

        if(_supportedAssets.length > _maximumSupportedAssetCount) revert AboveMax(_maximumSupportedAssetCount, _supportedAssets.length);
        if(_fees.management > maximumFees.management) revert AboveMax(maximumFees.management, _fees.management);
        if(_fees.performance > maximumFees.performance) revert AboveMax(maximumFees.performance, _fees.performance);
        if(_fees.entrance > maximumFees.entrance) revert AboveMax(maximumFees.entrance, _fees.entrance);
        if(_fees.exit > maximumFees.exit) revert AboveMax(maximumFees.exit, _fees.exit);

        // Combining into one line to fix stack too deep
        ERC1967Proxy seasonalFarm = new ERC1967Proxy(
            ClonesUpgradeable.clone(seasonalFarmImplementation),
            abi.encodeWithSignature(
                "initialize((bool,string,string,uint256,uint256,uint256,uint256),address)",
                _info,
                _operator
            )
        );

        ERC1967Proxy farmManagement = new ERC1967Proxy(
            ClonesUpgradeable.clone(farmManagementImplementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,(uint256,uint256,uint256,uint256),(address,bool)[])",
                address(this),
                _manager,
                address(seasonalFarm),
                _fees,
                _supportedAssets
            )
        );

        ISeasonalFarm farm = ISeasonalFarm(address(seasonalFarm));
        farm.setFarmManagement(address(farmManagement));
        deployedFarms.push(address(seasonalFarm));
        isFarm[address(seasonalFarm)] = true;

        emit FarmCreated(
            address(seasonalFarm),
            address(farmManagement),
            _manager,
            _info,
            _fees,
            FEE_DENOMINATOR,
            farm.endTime(),
            _operator
        );

        return address(seasonalFarm);
    }

    /// @notice Return the latest price of a given asset
    /// @param asset The address of the asset
    /// @return price The latest price of a given asset
    function getAssetPrice(address asset) external view override returns (uint256 price) {
        price = IAssetHandler(assetHandler).getUSDPrice(asset);
    }

    function assetValue(address asset, uint256 amount) external view returns (uint256) {
        uint256 price = this.getAssetPrice(asset);
        uint256 decimals = IERC20MetadataUpgradeable(asset).decimals();

        return price.mul(amount).div(10**decimals);
    }

    // Returns the balance of a given address in USD, 10^18
    function balanceOnDex(address operator) external view returns (int256) {
        IDexHandler handler = IDexHandler(dexHandler);
        return handler.getBalance(operator);
    }

    // @param asset: The address of the asset
    // @param value: The value of the asset in dollar, 10^18
    function convertValueToAsset(address asset, uint256 valueInDollar) external view returns (uint256) {
        uint256 decimals = IERC20MetadataUpgradeable(asset).decimals();
        uint256 price = this.getAssetPrice(asset);
        return valueInDollar.mul(10**decimals)/price;
    }

    /*//////////////////////////////////////////////////////////////
                          ASSET HANDLERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the asset handler address
    /// @param _assetHandler The address of the asset handler
    function setAssetHandler(address _assetHandler) external onlyOwner {
        _setAssetHandler(_assetHandler);
    }

    /// @notice Set the asset handler address internal call
    /// @param _assetHandler The address of the asset handler
    function _setAssetHandler(address _assetHandler) internal {
        require(_assetHandler != address(0), "Invalid assetHandler");

        assetHandler = _assetHandler;

        emit AssetHandlerSet(assetHandler);
    }

    function isValidAsset(address asset) public view override returns (bool) {
        return IAssetHandler(assetHandler).priceAggregators(asset) != address(0);
    }

    /// MANAGER FEE
    /// @notice Set the maximum manager fee
    /// @param numerator The numerator of the maximum manager fee
    function setMaximumManagementFee(uint256 numerator) external onlyOwner {
        _setMaximumManagementFee(numerator);
    }

    /// @notice Set the maximum manager fee internal call
    /// @param numerator The numerator of the maximum manager fee
    function _setMaximumManagementFee(uint256 numerator) internal {
        require(numerator <= FEE_DENOMINATOR, "invalid fraction");

        maximumFees.management = numerator;

        emit MaximumManagerFeeChanged(numerator, FEE_DENOMINATOR);
    }

    function getMaximumManagerFee() external view override returns (uint256, uint256) {
        return (maximumFees.management, FEE_DENOMINATOR);
    }

    /// PERFORMANCE FEE
    /// @notice Set the maximum performance fee
    /// @param numerator The numerator of the maximum performance fee
    function setMaximumPerformanceFee(uint256 numerator) external onlyOwner {
        _setMaximumPerformanceFee(numerator);
    }

    /// @notice Set the maximum performance fee internal call
    /// @param numerator The numerator of the maximum performance fee
    function _setMaximumPerformanceFee(uint256 numerator) internal {
        require(numerator <= FEE_DENOMINATOR, "invalid fraction");

        maximumFees.performance = numerator;

        emit MaximumPerformanceFeeChanged(numerator, FEE_DENOMINATOR);
    }

    function getMaximumPerformanceFee() external view override returns (uint256, uint256) {
        return (maximumFees.performance, FEE_DENOMINATOR);
    }

    /* /// @notice Set the maximum manager fee numerator change
    function setMaximumManagerFeeNumeratorChange(uint256 amount) public onlyOwner {
        maximumManagerFeeNumeratorChange = amount;

        emit MaximumManagerFeeNumeratorChangeUpdated(amount);
    }

    /// @notice Set manager fee numberator change delay
    /// @param delay The delay in seconds for the manager fee numerator change
    function setManagerFeeNumeratorChangeDelay(uint256 delay) public onlyOwner {
        managerFeeNumeratorChangeDelay = delay;

        emit ManagerFeeNumeratorChangeDelayUpdated(delay);
    } */

    /// ENTRANCE FEE
    /// @notice Set the maximum entrance fee
    /// @param _numerator The numerator of the maximum entrance fee
    function setMaximumEntranceFee(uint256 _numerator) external onlyOwner {
        _setMaximumEntranceFee(_numerator);
    }

    /// @notice Set the maximum entrance fee internal call
    /// @param _numerator The numer of the maximum entrance fee
    function _setMaximumEntranceFee(uint256 _numerator) internal {
        require(_numerator <= FEE_DENOMINATOR, "invalid fraction");

        maximumFees.entrance = _numerator;

        emit MaximumEntranceFeeChanged(_numerator, FEE_DENOMINATOR);
    }

    function getMaximumEntranceFee() external view override returns (uint256, uint256) {
        return (maximumFees.entrance, FEE_DENOMINATOR);
    }

    /// EXIT FEE
    /// @notice Set the maximum exit fee
    /// @param _numerator The numerator of the maximum exit fee
    function setMaximumExitFee(uint256 _numerator) external onlyOwner {
        _setMaximumExitFee(_numerator);
    }

    /// @notice Set the maximum exit fee internal call
    /// @param _numerator The numer of the maximum exit fee
    function _setMaximumExitFee(uint256 _numerator) internal {
        require(_numerator <= FEE_DENOMINATOR, "invalid fraction");

        maximumFees.exit = _numerator;

        emit MaximumExitFeeChanged(_numerator, FEE_DENOMINATOR);
    }

    function getMaximumExitFee() external view override returns (uint256, uint256) {
        return (maximumFees.exit, FEE_DENOMINATOR);
    }

    // PENALTY FEEs
    function getPenaltyFee(uint256 day) external view override returns (uint256, uint256) {
        return (penaltyFees[day], FEE_DENOMINATOR);
    }

    /// @notice Set the penalty fees
    function setPenaltyFees(uint256[] memory _newPenaltyFees) external onlyOwner {
        if(_newPenaltyFees.length != 3) revert InvalidLength(3);
        for (uint256 i = 0; i < _newPenaltyFees.length; i++) {
            if(_newPenaltyFees[i] >= FEE_DENOMINATOR) revert AboveMax(FEE_DENOMINATOR, _newPenaltyFees[i]);
        }

        penaltyFees = _newPenaltyFees;
    }

    /// @notice Set maximum supported asset count
    /// @param count The maximum supported asset count
    function setMaximumSupportedAssetCount(uint256 count) external onlyOwner {
        _setMaximumSupportedAssetCount(count);
    }

    /// @notice Set maximum supported asset count internal call
    /// @param count The maximum supported asset count
    function _setMaximumSupportedAssetCount(uint256 count) internal {
        _maximumSupportedAssetCount = count;

        emit MaximumSupportedAssetCountChanged(count);
    }

    function getMaximumSupportedAssetCount() external view virtual override returns (uint256) {
        return _maximumSupportedAssetCount;
    }

    function getCreateFarmDigest(
        address _operator,
        address _manager
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CREATE_FARM_HASH,
                        _operator,
                        _manager
                    )
                )
            );
    }

    function getDivestDigest(
        address _farm,
        address _asset,
        bytes memory _info
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        DIVEST_HASH,
                        _farm,
                        _asset,
                        _info
                    )
                )
            );
    }

    function recoverSigner(bytes memory signature, bytes32 digest) public pure returns(address) {
        return digest.toEthSignedMessageHash().recover(signature);
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