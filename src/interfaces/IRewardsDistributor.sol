// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVotingEscrow.sol";

interface IRewardsDistributor {
    function notifyRewardAmount(uint256 amount) external;
    function ve() external returns (IVotingEscrow);
    function claimable(uint256 _tokenId) external view returns (uint256);
}
