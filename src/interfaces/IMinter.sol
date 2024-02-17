// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMinter
 * @notice Interface for a Minter contract.
 * @dev This interface defines functions for interacting with a Minter contract.
 */
interface IMinter {
  /**
   * @notice Updates the period.
   * @return timestamp updated period.
   */
  function update_period() external returns (uint256);

  /**
   * @notice Checks if the Minter contract is active.
   * @return isTrue boolean indicating whether the Minter contract is active.
   */
  function check() external view returns (bool);

  /**
   * @notice Retrieves the current period.
   * @return timestamp current period.
   */
  function period() external view returns (uint256);

  /**
   * @notice Retrieves the active period.
   * @return timestamp active period.
   */
  function active_period() external view returns (uint256);
}
