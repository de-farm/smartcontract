//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISingleFarmFactory} from "./ISingleFarmFactory.sol";

interface ISingleFarm {
    /// @notice Enum to describe the trading status of the farm
    /// @dev NOT_OPENED - Not open
    /// @dev OPENED - opened position
    /// @dev CLOSED - closed position
    /// @dev LIQUIDATED - liquidated position
    /// @dev CANCELLED - did not start due to deadline reached
    enum SfStatus {
        NOT_OPENED,
        OPENED,
        CLOSED,
        LIQUIDATED,
        CANCELLED
    }

    event Deposited(address indexed investor, uint256 amount);
    event FundraisingClosed(uint256 amount);
    event PositionOpened(bytes info);
    event PositionClosed(uint256 balance);
    event Cancelled();
    event Liquidated();
    event Claimed(address indexed investor, uint256 amount);
    event FundDeadlineChanged(uint256 fundDeadline);
    event LinkedSigner(address farm, address signer);

    event StatusUpdated(address indexed by, ISingleFarm.SfStatus status);
    event TotalRaisedUpdated(address indexed by, uint256 totalRaised);
    event RemainingBalanceUpdated(address indexed by, uint256 remainingBalance);
    event OperatorUpdated(address indexed by, address operator);

    function deposit(uint256 amount) external;
    function closeFundraising() external;
    function openPosition(bytes calldata info) external;
    function closePosition(bytes calldata _signature) external;
    function cancelByAdmin() external;
    function cancelByManager() external;
    function liquidate() external;
    function claim() external;
    function setFundDeadline(uint256 newFundDeadline) external;

    function getUserAmount(address _investor) external view returns (uint256);
    function getClaimAmount(address _investor) external view returns (uint256);
    function claimableAmount(address _investor) external view returns (uint256);
    function getClaimed(address _investor) external view returns (bool);
    function remainingAmountAfterClose() external view returns (uint256);
}