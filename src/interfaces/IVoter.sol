// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVoter
 * @notice Interface for a Voter contract.
 * @dev This interface defines functions for interacting with a Voter contract.
 */
interface IVoter {
  /**
   * @notice Retrieves the address of the Voting Escrow contract.
   * @return The address of the Voting Escrow contract.
   */
  function _ve() external view returns (address);

  /**
   * @notice Retrieves the address of the governor contract.
   * @return The address of the governor contract.
   */
  function governor() external view returns (address);

  /**
   * @notice Retrieves the address of the gauge for a given pair.
   * @param _pair The address of the pair for which to retrieve the gauge.
   * @return The address of the gauge contract.
   */
  function gauges(address _pair) external view returns (address);

  /**
   * @notice Retrieves the address of the factory contract.
   * @return The address of the factory contract.
   */
  function factory() external view returns (address);

  /**
   * @notice Retrieves the address of the minter contract.
   * @return The address of the minter contract.
   */
  function minter() external view returns (address);

  /**
   * @notice Retrieves the address of the emergency council contract.
   * @return The address of the emergency council contract.
   */
  function emergencyCouncil() external view returns (address);

  /**
   * @notice Retrieves the address of the satellite Pools
   * @return The address of the emergency council contract.
   */
  function getLzPools() external view returns (address[] memory);

  // /**
  //  * @notice Emits a deposit event.
  //  * @param _tokenId The token ID.
  //  * @param account The address of the account.
  //  * @param amount The amount deposited.
  //  */
  // function emitDeposit(
  //   uint256 _tokenId,
  //   address account,
  //   uint256 amount
  // ) external;

  // /**
  //  * @notice Emits a withdraw event.
  //  * @param _tokenId The token ID.
  //  * @param account The address of the account.
  //  * @param amount The amount withdrawn.
  //  */
  // function emitWithdraw(
  //   uint256 _tokenId,
  //   address account,
  //   uint256 amount
  // ) external;

  /**
   * @notice Checks if a token is whitelisted.
   * @param token The address of the token to check.
   * @return A boolean indicating whether the token is whitelisted.
   */
  function isWhitelisted(address token) external view returns (bool);

  /**
   * @notice Notifies the reward amount.
   * @param amount The amount of reward.
   */
  function notifyRewardAmount(uint256 amount) external;

  /**
   * @notice Distributes rewards to a specific gauge.
   * @param _gauge The address of the gauge.
   */
  function distribute(address _gauge) external;

  /**
   * @notice Distributes rewards to all gauges.
   */
  function distributeAll() external;

  /**
   * @notice Distributes rewards within a specified range of gauges.
   * @param start The starting index of the gauges.
   * @param finish The ending index of the gauges.
   */
  function distribute(uint256 start, uint256 finish) external;

  /**
   * @notice Distributes fees to specified gauges.
   * @param _gauges The addresses of the gauges.
   */
  function distributeFees(address[] memory _gauges) external;

  /**
   * @notice Retrieves the address of the internal bribe contract for a specific gauge.
   * @param _gauge The address of the gauge.
   * @return The address of the internal bribe contract.
   */
  function internal_bribes(address _gauge) external view returns (address);

  /**
   * @notice Retrieves the address of the external bribe contract for a specific gauge.
   * @param _gauge The address of the gauge.
   * @return The address of the external bribe contract.
   */
  function external_bribes(address _gauge) external view returns (address);

  /**
   * @notice Retrieves the used weights for a specific account.
   * @param account The address of the account.
   * @return The used weights for the account.
   */
  function usedWeights(address account) external view returns (uint256);

  /**
   * @notice Checks if an account has voted.
   * @param _account The address of the account.
   * @return A boolean indicating whether the account has voted.
   */
  function hasVoted(address _account) external view returns (bool);

  /**
   * @notice Retrieves the timestamp of the last vote for a specific account.
   * @param account The address of the account.
   * @return The timestamp of the last vote.
   */
  function lastVoted(address account) external view returns (uint256);

  /**
   * @notice Retrieves the pair voted by an account at a specific index.
   * @param account The address of the account.
   * @param _index The index of the pair.
   * @return _pair address of the pair voted by the account.
   */
  function poolVote(
    address account,
    uint256 _index
  ) external view returns (address _pair);

  /**
   * @notice Retrieves the votes for a specific account and pair.
   * @param account The address of the account.
   * @param _pool The address of the pair.
   * @return votes votes for the account and pair.
   */
  function votes(
    address account,
    address _pool
  ) external view returns (uint256 votes);

  /**
   * @notice Retrieves the length of pool votes for a specific account.
   * @param account The address of the account.
   * @return The length of pool votes.
   */
  function poolVoteLength(address account) external view returns (uint256);

  /**
   * @notice Retrieves the total number of pools.
   * @return The total number of pools.
   */
  function length() external view returns (uint256);

  /**
   * @notice Retrieves the incentivized pools.
   * @return An array of incentivized pool addresses.
   */
  function getIncentivizedPools() external view returns (address[] memory);

  /**
   * @notice Checks if a contract is a bribe contract.
   * @param _bribe The address of the bribe contract.
   * @return isTrue boolean indicating whether the contract is a bribe contract.
   */
  function isBribe(address _bribe) external view returns (bool);

  /**
   * @notice Checks if a gauge is alive.
   * @param gauge The address of the gauge.
   * @return isTrue boolean indicating whether the gauge is alive.
   */
  function isAlive(address gauge) external view returns (bool);

  /**
   * @notice Resets the votes for the message sender
   */
  function reset() external;

  /**
   * @notice poke the votes
   */
  function poke() external;
}
