// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./Managed.sol";
import "./interfaces/ISeasonalFarm.sol";
import "./interfaces/IFarmManagement.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "../interfaces/IWhitelistedTokens.sol";

contract FarmManagement is
    IFarmManagement, IHasSupportedAsset,
    Managed
{
    using SafeMathUpgradeable for uint256;

    // All events must be accompanied by the farm address
    event AssetAdded(address indexed farm, address manager, address asset, bool isDeposit);
    event AssetRemoved(address farm, address manager, address asset);
    event ManagementFeeSet(address farm, address manager, uint256 numerator, uint256 denominator);
    event PerformanceFeeSet(address farm, address manager, uint256 numerator, uint256 denominator);
    event EntranceFeeSet(address farm, address manager, uint256 numerator, uint256 denominator);
    event ExitFeeSet(address farm, address manager, uint256 numerator, uint256 denominator);

    address public factory;
    address public farm;
    IHasFeeInfo.Fees private fees;

    /*//////////////////////////////////////////////////////////////
                            SUPPORTED ASSETS
    //////////////////////////////////////////////////////////////*/
    Asset[] public supportedAssets;
    mapping(address => uint256) public assetPosition; // maps the asset to its 1-based position

    function initialize(
        address _factory,
        address _manager,
        address _farm,
        IHasFeeInfo.Fees memory _fees,
        Asset[] calldata _supportedAssets
    ) public initializer {
        require(_factory != address(0), "Invalid factory");
        require(_manager != address(0), "Invalid manager");
        require(_farm != address(0), "Invalid farm");

        factory = _factory;
        farm = _farm;
        fees = _fees;
        __Managed_init(_manager);

        _changeAssets(_supportedAssets, new address[](0));
    }

    function isSupportedAsset(address asset) public view override returns (bool) {
        return assetPosition[asset] != 0;
    }

    function isDepositAsset(address asset) external view returns (bool) {
        uint256 index = assetPosition[asset];
        return index != 0 && supportedAssets[index.sub(1)].isDeposit;
    }

    function changeAssets(Asset[] calldata _addAssets, address[] calldata _removeAssets) external onlyManager {
        _changeAssets(_addAssets, _removeAssets);
    }

    function _changeAssets(Asset[] calldata _addAssets, address[] memory _removeAssets) internal {
        for (uint8 i = 0; i < _removeAssets.length; i++) {
            _removeAsset(_removeAssets[i]);
        }

        for (uint8 i = 0; i < _addAssets.length; i++) {
            _addAsset(_addAssets[i]);
        }

        require(
            supportedAssets.length <= IHasAssetInfo(factory).getMaximumSupportedAssetCount(),
            "maximum assets reached"
        );

        require(getDepositAssets().length >= 1, "at least one deposit asset");
    }

    function _addAsset(Asset calldata _asset) internal {
        address asset = _asset.asset;
        bool isDeposit = _asset.isDeposit;

        require(IWhitelistedTokens(factory).isTokenAllowed(asset), "invalid asset");

        if (isSupportedAsset(asset)) {
            uint256 index = assetPosition[asset].sub(1);
            supportedAssets[index].isDeposit = isDeposit;
        } else {
            supportedAssets.push(Asset(asset, isDeposit));
            assetPosition[asset] = supportedAssets.length;
        }

        emit AssetAdded(farm, manager, asset, isDeposit);
    }

    /// @notice Remove asset from the pool
    /// @dev use asset address to remove from supportedAssets
    /// @param asset asset address
    function _removeAsset(address asset) internal {
        require(isSupportedAsset(asset), "asset not supported");

        require(assetBalance(asset) == 0, "cannot remove non-empty asset");

        uint256 length = supportedAssets.length;
        Asset memory lastAsset = supportedAssets[length.sub(1)];
        uint256 index = assetPosition[asset].sub(1); // adjusting the index because the map stores 1-based

        // overwrite the asset to be removed with the last supported asset
        supportedAssets[index] = lastAsset;
        assetPosition[lastAsset.asset] = index.add(1); // adjusting the index to be 1-based
        assetPosition[asset] = 0; // update the map

        // delete the last supported asset and resize the array
        supportedAssets.pop();

        emit AssetRemoved(farm, manager, asset);
    }

    function getSupportedAssets() external view override returns (Asset[] memory) {
        return supportedAssets;
    }

    function getDepositAssets() public view returns (address[] memory) {
        uint256 assetCount = supportedAssets.length;
        address[] memory depositAssets = new address[](assetCount);
        uint8 index = 0;

        for (uint8 i = 0; i < assetCount; i++) {
            if (supportedAssets[i].isDeposit) {
                depositAssets[index] = supportedAssets[i].asset;
                index++;
            }
        }

        // Reduce length for withdrawnAssets to remove the empty items
        uint256 reduceLength = assetCount.sub(index);
        assembly {
            mstore(depositAssets, sub(mload(depositAssets), reduceLength))
        }

        return depositAssets;
    }

    function getManagementFee() external view override returns (uint256, uint256) {
        (, uint256 managerFeeDenominator) = IHasFeeInfo(factory).getMaximumManagerFee();
        return (fees.management, managerFeeDenominator);
    }

    /// @notice Manager can set management fee
    function setManagementFee(uint256 numerator) external onlyManager {
        (uint256 maximumNumerator, uint256 maximumDenominator) = IHasFeeInfo(factory).getMaximumManagerFee();
        require(numerator <= maximumDenominator && numerator <= maximumNumerator, "invalid management fee");

        fees.management = numerator;

        emit ManagementFeeSet(farm, manager, numerator, maximumDenominator);
    }

    function getPerformanceFee() external view override returns (uint256, uint256) {
        (, uint256 performanceFeeDenominator) = IHasFeeInfo(factory).getMaximumPerformanceFee();
        return (fees.performance, performanceFeeDenominator);
    }

    /// @notice Manager can set performance fee
    function setPerformanceFee(uint256 numerator) external onlyManager {
        (uint256 maximumNumerator, uint256 maximumDenominator) = IHasFeeInfo(factory).getMaximumPerformanceFee();
        require(numerator <= maximumDenominator && numerator <= maximumNumerator, "invalid performance fee");

        fees.performance = numerator;

        emit PerformanceFeeSet(farm, manager, numerator, maximumDenominator);
    }

    function getEntranceFee() external view override returns (uint256, uint256) {
        (, uint256 entranceFeeDenominator) = IHasFeeInfo(factory).getMaximumEntranceFee();
        return (fees.entrance, entranceFeeDenominator);
    }

    /// @notice Manager can set entrance fee
    function setEntranceFee(uint256 numerator) external onlyManager {
        (uint256 maximumNumerator, uint256 maximumDenominator) = IHasFeeInfo(factory).getMaximumEntranceFee();
        require(numerator <= maximumDenominator && numerator <= maximumNumerator, "invalid entrance fee");

        fees.entrance = numerator;

        emit EntranceFeeSet(farm, manager, numerator, maximumDenominator);
    }

    function getExitFee() external view override returns (uint256, uint256) {
        (, uint256 exitFeeDenominator) = IHasFeeInfo(factory).getMaximumExitFee();
        return (fees.entrance, exitFeeDenominator);
    }

    /// @notice Manager can set exit fee
    function setExitFee(uint256 numerator) external onlyManager {
        (uint256 maximumNumerator, uint256 maximumDenominator) = IHasFeeInfo(factory).getMaximumExitFee();
        require(numerator <= maximumDenominator && numerator <= maximumNumerator, "invalid exit fee");

        fees.exit = numerator;

        emit ExitFeeSet(farm, manager, numerator, maximumDenominator);
    }

    /// @notice Get asset balance(including any balance in operator)
    function assetBalance(address asset) public view returns (uint256) {
        ISeasonalFarm seasonalFarm = ISeasonalFarm(farm);
        return _assetBalance(asset, seasonalFarm.operator());
    }

    /// @notice Get asset balance(including any balance in operator)
    function _assetBalance(address asset, address operator) internal view returns (uint256) {
        IERC20Upgradeable erc20 = IERC20Upgradeable(asset);
        return erc20.balanceOf(farm) + erc20.balanceOf(operator);
    }

    /// @notice Return the total fund value of the pool
    /// @dev Calculate the total fund value: asssets of the pool and on the dex account
    /// @return value in Dollar
    function totalFundValue() external view override returns (uint256) {
        ISeasonalFarm seasonalFarm = ISeasonalFarm(farm);
        IHasAssetInfo assetInfo = IHasAssetInfo(factory);
        uint256 total = 0;
        uint256 assetCount = supportedAssets.length;

        // Calculate the total value of the assets in the pool
        for (uint256 i = 0; i < assetCount; i++) {
            address asset = supportedAssets[i].asset;
            total = total.add(assetInfo.assetValue(asset, _assetBalance(asset, seasonalFarm.operator())));
        }

        // Get the total value of the assets on the dex
        int256 balance = assetInfo.balanceOnDex(seasonalFarm.operator());

        if (balance > 0) total = total.add(uint256(balance));
        else {
            if(uint256(-balance) >= total) total = 0;
            else total = total.sub(uint256(-balance));
        }

        return total;
    }

    /// @notice Return the total assets value of the pool
    /// @return value in Dollar
    function totalAssetValue() external view returns (uint256) {
        IHasAssetInfo assetInfo = IHasAssetInfo(factory);
        uint256 total = 0;
        uint256 assetCount = supportedAssets.length;
        ISeasonalFarm seasonalFarm = ISeasonalFarm(farm);

        // Calculate the total value of the assets in the pool
        for (uint256 i = 0; i < assetCount; i++) {
            address asset = supportedAssets[i].asset;
            total = total.add(assetInfo.assetValue(asset, _assetBalance(asset, seasonalFarm.operator())));
        }

        return total;
    }

    /// @notice Return the total assets value of the pool on the dex account
    /// @return balance in Dollar
    function totalBalanceOnDex() external view returns (int256 balance) {
        IHasAssetInfo assetInfo = IHasAssetInfo(factory);
        ISeasonalFarm seasonalFarm = ISeasonalFarm(farm);

        balance = assetInfo.balanceOnDex(seasonalFarm.operator());
    }
}