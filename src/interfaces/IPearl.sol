// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IPearl
 * @notice Interface for the Pearl token contract.
 * @dev This interface defines functions for interacting with a Pearl token contract.
 */
interface IPearl {
  /**
   * @notice Retrieves the total supply of Pearl tokens.
   * @return The total supply of Pearl tokens.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @notice Retrieves the balance of Pearl tokens for a given address.
   * @param account The address for which to retrieve the balance.
   * @return The balance of Pearl tokens for the given address.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @notice Approves another address to spend Pearl tokens on behalf of the owner.
   * @param spender The address to which approval is granted.
   * @param value The amount of Pearl tokens to approve for spending.
   * @return A boolean indicating whether the approval was successful.
   */
  function approve(address spender, uint256 value) external returns (bool);

  /**
   * @notice Transfers Pearl tokens from the sender's address to the specified recipient.
   * @param recipient The address to which Pearl tokens will be transferred.
   * @param amount The amount of Pearl tokens to transfer.
   * @return A boolean indicating whether the transfer was successful.
   */
  function transfer(address recipient, uint256 amount) external returns (bool);

  /**
   * @notice Transfers Pearl tokens from one address to another.
   * @param sender The address from which to transfer Pearl tokens.
   * @param recipient The address to which Pearl tokens will be transferred.
   * @param amount The amount of Pearl tokens to transfer.
   * @return A boolean indicating whether the transfer was successful.
   */
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  /**
   * @notice Mints new Pearl tokens and assigns them to a recipient.
   * @param to The address to which newly minted Pearl tokens will be assigned.
   * @param amount The amount of Pearl tokens to mint.
   */
  function mint(address to, uint256 amount) external;

  /**
   * @notice Retrieves the address of the minter contract.
   * @return The address of the minter contract.
   */
  function minter() external returns (address);
}
