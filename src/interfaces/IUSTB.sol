// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
/**
 * @title IUSTB
 * @notice Interface for the USTB token contract.
 * @dev This interface defines functions for interacting with a USTB token contract.
 */
interface IUSTB {
  function disableRebase(address account, bool disable) external;
  function optedOut(address account) external view returns (bool);
}
