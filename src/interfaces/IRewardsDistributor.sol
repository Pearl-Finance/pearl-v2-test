// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVotingEscrow.sol";

/**
 * @title IRewardsDistributor
 * @notice Interface for a Rewards Distributor contract.
 * @dev This interface defines functions for interacting with a Rewards Distributor contract.
 */
interface IRewardsDistributor {
    /**
     * @notice Notifies the distribution of a reward amount.
     * @param amount The amount of reward to distribute.
     */
    function notifyRewardAmount(uint256 amount) external;

    /**
     * @notice Retrieves the Voting Escrow contract.
     * @return The address of the Voting Escrow contract.
     */
    function ve() external returns (IVotingEscrow);

    /**
     * @notice Retrieves the claimable reward for a given token ID.
     * @param _tokenId The token ID for which to check the claimable reward.
     * @return The claimable reward amount for the specified token ID.
     */
    function claimable(uint256 _tokenId) external view returns (uint256);

    function claim(uint256 tokenId) external returns (uint256 amount);
}
