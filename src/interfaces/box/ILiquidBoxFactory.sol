// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidBoxFactory
 * @notice Interface for Liquid Box Factory contract.
 * @dev This interface defines functions for interacting with a Liquid Box Factory contract, which is responsible for creating and managing liquidity box contracts.
 */
interface ILiquidBoxFactory {
  /**
   * @dev Returns the address of a liquidity box contract for the given token pair and fee.
   * @param token0 The address of the first token.
   * @param token1 The address of the second token.
   * @param fee The fee of the liquidity box.
   * @return The address of the liquidity box contract.
   */
  function getBox(
    address token0,
    address token1,
    uint24 fee
  ) external view returns (address);

  /**
   * @dev Sets the manager address for the factory contract.
   * @param manager The address of the manager.
   */
  function setManager(address manager) external;

  /**
   * @dev Sets the box manager address for the factory contract.
   * @param boxManager The address of the box manager.
   */
  function setBoxManager(address boxManager) external;

  /**
   * @dev Returns the address of the box manager.
   * @return The address of the box manager.
   */
  function boxManager() external view returns (address);
}
