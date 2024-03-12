// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidBoxCallback
 */
interface ILiquidBoxCallback {
  function boxDepositCallback(
    uint256 amount0Owed,
    uint256 amount1Owed,
    address payer
  ) external;
}
