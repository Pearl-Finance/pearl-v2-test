// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEpochController
 * @notice Interface for a EpochController contract.
 * @dev This interface defines functions for interacting with a EpochController contract.
 */
interface IEpochController {
    /**
     * @notice Checks if the EpochController contract is distributing emissions.
     * @return isTrue boolean indicating whether the emissions distribution is active.
     */
    function checkDistribution() external view returns (bool);
}
