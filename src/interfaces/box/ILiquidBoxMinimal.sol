// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface ILiquidBoxMinimal is IERC20Upgradeable {
    /**
     * @notice Calculates the amounts of lqiuidity in the pool for each share.
     * @return liquidityPerShare The calculated liquidity of shares for the recipient.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getPoolLiquidityPerShare() external view returns (uint256 liquidityPerShare);

    function baseLower() external view returns (int24);

    function baseUpper() external view returns (int24);

    function claimFees(address from, address to) external returns (uint256 claimable0, uint256 claimable1);

    /**
     * @notice Calculates the amounts of token0 and token1 using shares for a given recipient address.
     * @param shares The amount of shares
     * @return amount0 The calculated amount of token0 shares for the recipient.
     * @return amount1 The calculated amount of token1 shares for the recipient.
     * @return liquidity The calculated liquidity of shares for the recipient.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getSharesAmount(uint256 shares)
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    function earnedFees(address account) external view returns (uint256 amount0, uint256 amount1);
}
