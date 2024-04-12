//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISingleFarmFactory {
    event FarmFactoryInitialized(
        address singleFarmImplementation,
        uint256 capacityPerFarm,
        uint256 minInvestmentAmount,
        uint256 maxInvestmentAmount,
        uint256 ethFee,
        uint256 maxManagerFeeNumerator,
        uint256 maxManagerFeeDenominator,
        address usdc,
        address admin,
        address treasury,
        address deFarmSeeds
    );

    event FarmCreated(
        address indexed farm,
        address indexed baseToken,
        uint256 fundraisingPeriod,
        uint256 entryPrice,
        uint256 targetPrice,
        uint256 liquidationPrice,
        bool tradeDirection,
        address indexed manager,
        uint256 managerFeeNumerator,
        uint256 managerFeeDenominator,
        uint256 time,
        bool isPrivate
    );

    event CapacityPerFarmChanged(uint256 capacity);
    event MaxInvestmentAmountChanged(uint256 maxAmount);
    event MinInvestmentAmountChanged(uint256 maxAmount);
    event MaxLeverageChanged(uint256 maxLeverage);
    event MinLeverageChanged(uint256 minLeverage);
    event MaxFundraisingPeriodChanged(uint256 maxFundraisingPeriod);
    event MaxManagerFeeChanged(uint256 maxManagerFee);
    event FarmImplementationChanged(address indexed df);
    event UsdcAddressChanged(address indexed usdc);
    event DefarmSeedsAddressChanged(address indexed deFarmSeeds);

    struct Sf {
        address baseToken;
        bool tradeDirection; // Long/Short
        uint256 fundraisingPeriod;
        uint256 entryPrice;
        uint256 targetPrice;
        uint256 liquidationPrice;
    }

    function createFarm(Sf calldata _sf, uint256 _managerFee, bool _isPrivate) external payable returns (address);

    function setCapacityPerFarm(uint256 _capacity) external;

    function setMinInvestmentAmount(uint256 _amount) external;

    function setMaxInvestmentAmount(uint256 _amount) external;

    function setMaxManagerFee(uint256 _managerFee) external;

    function setSfImplementation(address _sf) external;
}