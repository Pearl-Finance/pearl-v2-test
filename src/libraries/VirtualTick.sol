// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { SafeCast } from "./SafeCast.sol";

import { TickMath } from "./TickMath.sol";

/// @title Tick
/// @notice Contains functions for managing tick processes and relevant calculations
library VirtualTick {
  error LO();

  using SafeCast for int256;

  // info stored for each initialized individual tick
  struct Info {
    // the total position liquidity that references this tick
    uint128 liquidityGross;
    // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
    int128 liquidityNet;
    // rewards growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint256 rewardsGrowthOutsideX128;
    // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint160 secondsPerLiquidityOutsideX128;
    bool initialized;
  }

  /// @notice Derives max liquidity per tick from given tick spacing
  /// @dev Executed within the pool constructor
  /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
  ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
  /// @return The max liquidity per tick
  function tickSpacingToMaxLiquidityPerTick(
    int24 tickSpacing
  ) internal pure returns (uint128) {
    unchecked {
      int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
      int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
      uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
      return type(uint128).max / numTicks;
    }
  }

  /// @notice Retrieves rewards growth data
  /// @param self The mapping containing all tick information for initialized ticks
  /// @param tickLower The lower tick boundary of the position
  /// @param tickUpper The upper tick boundary of the position
  /// @param tickCurrent The current tick
  /// @param rewardsGrowthGlobalX128 The all-time global fee growth, per unit of liquidity, in token0
  /// @return rewardsGrowthInsideX128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
  function getrewardsGrowthInside(
    mapping(int24 => VirtualTick.Info) storage self,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent,
    uint256 rewardsGrowthGlobalX128
  ) internal view returns (uint256 rewardsGrowthInsideX128) {
    unchecked {
      Info storage lower = self[tickLower];
      Info storage upper = self[tickUpper];

      // if (tickCurrent < tickUpper) {
      //   if (tickCurrent >= tickLower) {
      //     rewardsGrowthInsideX128 =
      //       rewardsGrowthGlobalX128 -
      //       lower.rewardsGrowthOutsideX128;
      //   } else {
      //     rewardsGrowthInsideX128 = lower.rewardsGrowthOutsideX128;
      //   }
      //   rewardsGrowthInsideX128 -= upper.rewardsGrowthOutsideX128;
      // } else {
      //   rewardsGrowthInsideX128 =
      //     upper.rewardsGrowthOutsideX128 -
      //     lower.rewardsGrowthOutsideX128;
      // }

      // calculate fee growth below
      uint256 rewardsGrowthBelowX128;
      if (tickCurrent >= tickLower) {
        rewardsGrowthBelowX128 = lower.rewardsGrowthOutsideX128;
      } else {
        rewardsGrowthBelowX128 =
          rewardsGrowthGlobalX128 -
          lower.rewardsGrowthOutsideX128;
      }

      // calculate fee growth above
      uint256 rewardsGrowthAboveX128;
      if (tickCurrent < tickUpper) {
        rewardsGrowthAboveX128 = upper.rewardsGrowthOutsideX128;
      } else {
        rewardsGrowthAboveX128 =
          rewardsGrowthGlobalX128 -
          upper.rewardsGrowthOutsideX128;
      }

      rewardsGrowthInsideX128 =
        rewardsGrowthGlobalX128 -
        rewardsGrowthBelowX128 -
        rewardsGrowthAboveX128;
    }
  }

  /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
  /// @param self The mapping containing all tick information for initialized ticks
  /// @param tick The tick that will be updated
  /// @param tickCurrent The current tick
  /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
  /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
  /// @param maxLiquidity The maximum liquidity allocation for a single tick
  /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
  function update(
    mapping(int24 => VirtualTick.Info) storage self,
    int24 tick,
    int24 tickCurrent,
    int128 liquidityDelta,
    uint256 rewardsGrowthGlobalX128,
    bool upper,
    uint128 maxLiquidity
  ) internal returns (bool flipped) {
    VirtualTick.Info storage info = self[tick];

    uint128 liquidityGrossBefore = info.liquidityGross;
    uint128 liquidityGrossAfter = liquidityDelta < 0
      ? liquidityGrossBefore - uint128(-liquidityDelta)
      : liquidityGrossBefore + uint128(liquidityDelta);

    if (liquidityGrossAfter > maxLiquidity) revert LO();

    flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

    if (liquidityGrossBefore == 0) {
      // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
      if (tick <= tickCurrent) {
        info.rewardsGrowthOutsideX128 = rewardsGrowthGlobalX128;
      }
      info.initialized = true;
    }

    info.liquidityGross = liquidityGrossAfter;

    // when the lower (upper) tick is crossed left to right (right to left), liquidity must be added (removed)
    info.liquidityNet = upper
      ? info.liquidityNet - liquidityDelta
      : info.liquidityNet + liquidityDelta;
  }

  /// @notice Clears tick data
  /// @param self The mapping containing all initialized tick information for initialized ticks
  /// @param tick The tick that will be cleared
  function clear(
    mapping(int24 => VirtualTick.Info) storage self,
    int24 tick
  ) internal {
    delete self[tick];
  }

  /// @notice Transitions to next tick as needed by price movement
  /// @param self The mapping containing all tick information for initialized ticks
  /// @param tick The destination tick of the transition
  /// @param rewardsGrowthGlobalX128 The all-time global reward growth, per unit of liquidity, in reward token
  /// @return liquidityNet The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
  function cross(
    mapping(int24 => VirtualTick.Info) storage self,
    int24 tick,
    uint256 rewardsGrowthGlobalX128
  ) internal returns (int128 liquidityNet) {
    unchecked {
      VirtualTick.Info storage info = self[tick];
      info.rewardsGrowthOutsideX128 =
        rewardsGrowthGlobalX128 -
        info.rewardsGrowthOutsideX128;
      liquidityNet = info.liquidityNet;
    }
  }
}
