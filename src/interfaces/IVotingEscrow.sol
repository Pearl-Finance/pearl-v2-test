// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC721Metadata} from "openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IVotes} from "openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title IVotingEscrow
 * @notice Interface for a Voting Escrow contract.
 * @dev This interface extends ERC721Enumerable, ERC721Metadata, and Votes interfaces.
 */
interface IVotingEscrow is IERC721Enumerable, IERC721Metadata, IVotes {
    struct VestingSchedule {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
    }

    /**
     * @notice Retrieves the maximum vesting duration.
     * @return The maximum vesting duration.
     */
    function MAX_VESTING_DURATION() external view returns (uint256);

    /**
     * @notice Retrieves the token locked in the escrow.
     * @return The address of the locked token contract.
     */
    function lockedToken() external view returns (IERC20);

    /**
     * @notice Retrieves the locked amount of a token.
     * @param tokenId The ID of the token.
     * @return The locked amount of the token.
     */
    function getLockedAmount(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Retrieves the minting timestamp of a token.
     * @param tokenId The ID of the token.
     * @return The minting timestamp of the token.
     */
    function getMintingTimestamp(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice Retrieves the total voting power at a specific timepoint.
     * @param timepoint The timepoint for which to retrieve the total voting power.
     * @return The total voting power at the specified timepoint.
     */
    function getPastTotalVotingPower(
        uint256 timepoint
    ) external view returns (uint256);

    /**
     * @notice Retrieves the voting power of a token at a specific timepoint.
     * @param tokenId The ID of the token.
     * @param timepoint The timepoint for which to retrieve the voting power.
     * @return The voting power of the token at the specified timepoint.
     */
    function getPastVotingPower(
        uint256 tokenId,
        uint256 timepoint
    ) external view returns (uint256);

    /**
     * @notice Retrieves the remaining vesting duration of a token.
     * @param tokenId The ID of the token.
     * @return The remaining vesting duration of the token.
     */
    function getRemainingVestingDuration(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice Mints a new token with vesting schedule.
     * @param receiver The address to receive the minted token.
     * @param lockedBalance The amount of token to be locked.
     * @param vestingDuration The duration of vesting in seconds.
     * @return The ID of the newly minted token.
     */
    function mint(
        address receiver,
        uint208 lockedBalance,
        uint256 vestingDuration
    ) external returns (uint256);

    /**
     * @notice Burns a token and releases locked funds to the receiver.
     * @param receiver The address to receive the released funds.
     * @param tokenId The ID of the token to burn.
     */
    function burn(address receiver, uint256 tokenId) external;

    /**
     * @notice Deposits additional funds to an existing token.
     * @param tokenId The ID of the token.
     * @param amount The amount of funds to deposit.
     */
    function depositFor(uint256 tokenId, uint256 amount) external;

    /**
     * @notice Merges tokens, transferring locked funds from one token to another.
     * @param tokenId The ID of the token to merge from.
     * @param intoTokenId The ID of the token to merge into.
     */
    function merge(uint256 tokenId, uint256 intoTokenId) external;

    /**
     * @notice Splits a token into multiple tokens.
     * @param tokenId The ID of the token to split.
     * @param shares The array of amounts to split into.
     * @return An array of newly minted token IDs.
     */
    function split(
        uint256 tokenId,
        uint256[] calldata shares
    ) external returns (uint256[] memory);

    /**
     * @notice Updates the vesting duration of a token.
     * @param tokenId The ID of the token.
     * @param newDuration The new vesting duration in seconds.
     */
    function updateVestingDuration(
        uint256 tokenId,
        uint256 newDuration
    ) external;

    /**
     * @notice Retrieves the address of the vesting contract.
     * @return The address of the vesting contract.
     */
    function vestingContract() external view returns (address);
}
