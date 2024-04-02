// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../interfaces/IVotingEscrow.sol";

interface IVesting {
  function getSchedule(
    uint256 tokenId
  )
    external
    view
    returns (IVotingEscrow.VestingSchedule memory vestingSchedule);
}
