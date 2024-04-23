// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.8 <0.9.0;

import "./FullMath.sol";
import "../interfaces/dex/IPearlV2Pool.sol";
import "./FixedPoint128.sol";

/// @title Returns information about the token value held in a Pearl V2 position
library PositionFees {
    function getFees(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 positionFeeGrowthInside0LastX128,
        uint256 positionFeeGrowthInside1LastX128
    ) internal view returns (uint256 amount0, uint256 amount1) {
        unchecked {
            (uint256 poolFeeGrowthInside0LastX128, uint256 poolFeeGrowthInside1LastX128) =
                _getFeeGrowthInside(IPearlV2Pool(pool), tickLower, tickUpper);

            amount0 = FullMath.mulDiv(
                poolFeeGrowthInside0LastX128 - positionFeeGrowthInside0LastX128, liquidity, FixedPoint128.Q128
            );

            amount1 = FullMath.mulDiv(
                poolFeeGrowthInside1LastX128 - positionFeeGrowthInside1LastX128, liquidity, FixedPoint128.Q128
            );
        }
    }

    function _getFeeGrowthInside(IPearlV2Pool pool, int24 tickLower, int24 tickUpper)
        private
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        unchecked {
            (, int24 tickCurrent,,,,,) = pool.slot0();
            (,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,) = pool.ticks(tickLower);
            (,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,) = pool.ticks(tickUpper);

            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent < tickUpper) {
                uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
                uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            }
        }
    }
}
