// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC721Metadata} from "openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IVotes} from "openzeppelin/contracts/governance/utils/IVotes.sol";

interface IVotingEscrow is IERC721Enumerable, IERC721Metadata, IVotes {
    struct VestingSchedule {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
    }

    function MAX_VESTING_DURATION() external view returns (uint256);

    function lockedToken() external view returns (IERC20);

    function getLockedAmount(uint256 tokenId) external view returns (uint256);

    function getMintingTimestamp(
        uint256 tokenId
    ) external view returns (uint256);

    function getPastTotalVotingPower(
        uint256 timepoint
    ) external view returns (uint256);

    function getPastVotingPower(
        uint256 tokenId,
        uint256 timepoint
    ) external view returns (uint256);

    function getRemainingVestingDuration(
        uint256 tokenId
    ) external view returns (uint256);

    function mint(
        address receiver,
        uint208 lockedBalance,
        uint256 vestingDuration
    ) external returns (uint256);

    function burn(address receiver, uint256 tokenId) external;

    function depositFor(uint256 tokenId, uint256 amount) external;

    function merge(uint256 tokenId, uint256 intoTokenId) external;

    function split(
        uint256 tokenId,
        uint256[] calldata shares
    ) external returns (uint256[] memory);

    function updateVestingDuration(
        uint256 tokenId,
        uint256 newDuration
    ) external;

    function vestingContract() external view returns (address);
}
