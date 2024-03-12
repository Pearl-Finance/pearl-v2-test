// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/**
 * @title ILiquidBoxMinimal
 * @notice Interface for minimal functionality of a Liquid Box contract.
 * @dev This interface extends the ERC20 interface and defines additional functions for interacting with a Liquid Box contract.
 */

interface ILiquidBoxMinimal is IERC20Upgradeable {
    /**
     * @notice Calculates the amount of liquidity in the pool per share.
     * @return liquidityPerShare The calculated liquidity per share.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getPoolLiquidityPerShare() external view returns (uint256 liquidityPerShare);

    /**
     * @notice Returns the lower tick boundary of the base position.
     * @return baseLower The lower tick boundary of the base position as an int24.
     */
    function baseLower() external view returns (int24);

    /**
     * @notice Returns the upper tick boundary of the base position.
     * @return baseUpper The upper tick boundary of the base position as an int24.
     */
    function baseUpper() external view returns (int24);

    /**
     * @notice Claims fees accrued in the box and transfers them to the recipient.
     * @param from The address from which to claim fees.
     * @param to The address to which the fees will be transferred.
     * @return claimable0 The amount of token0 fees claimed.
     * @return claimable1 The amount of token1 fees claimed.
     */
    function claimFees(address from, address to) external returns (uint256 claimable0, uint256 claimable1);

    /**
     * @notice Calculates the amounts of token0 and token1 using shares for a given recipient address.
     * @param shares The amount of shares to convert.
     * @return amount0 The calculated amount of token0 shares for the recipient.
     * @return amount1 The calculated amount of token1 shares for the recipient.
     * @return liquidity The calculated liquidity of shares for the recipient.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getSharesAmount(uint256 shares)
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @notice Returns the amount of earned fees for a specific account.
     * @param account The address of the account to check for earned fees.
     * @return amount0 The amount of token0 fees earned by the account.
     * @return amount1 The amount of token1 fees earned by the account.
     */
    function earnedFees(address account) external view returns (uint256 amount0, uint256 amount1);
}
