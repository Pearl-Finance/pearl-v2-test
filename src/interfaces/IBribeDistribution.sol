// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/**
 * @title IBribeDistribution
 * @notice Interface for distributing bribes.
 */
interface IBribeDistribution {
  /**
   * @notice Deposits vote into the contract for a specified token ID.
   * @param amount The amount to deposit.
   * @param tokenId The token ID to deposit for.
   */
  function _deposit(uint256 amount, uint256 tokenId) external;

  /**
   * @notice Withdraws vote from the contract for a specified token ID.
   * @param amount The amount to withdraw.
   * @param tokenId The token ID to withdraw from.
   */
  function _withdraw(uint256 amount, uint256 tokenId) external;

  /**
   * @notice Gets the rewards for the owner of the contract.
   * @param tokenId The token ID for which to get rewards.
   * @param tokens The list of reward tokens to get rewards for.
   */
  function getRewardForOwner(uint256 tokenId, address[] memory tokens) external;

  /**
   * @notice Notifies the contract about the amount of rewards to be distributed.
   * @param token The address of the token for which rewards are being distributed.
   * @param amount The amount of rewards to be distributed.
   */
  function notifyRewardAmount(address token, uint256 amount) external;

  /**
   * @notice Gets the remaining balance of a specific token.
   * @param token The address of the token.
   * @return The remaining balance of the token.
   */
  function left(address token) external view returns (uint256);

  /**
   * @notice Recovers ERC20 tokens in case of emergency.
   * @param tokenAddress The address of the ERC20 token to recover.
   * @param tokenAmount The amount of tokens to recover.
   */
  function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

  /**
   * @notice Sets the owner address.
   * @param _owner The address of the owner.
   */
  function setOwner(address _owner) external;
}
