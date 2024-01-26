// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface ILiquidBox {
    function initialize(
        address pool,
        address owner,
        address boxFactory,
        string memory name,
        string memory symbol
    ) external;

    /**
     * @notice Deposits tokens into the vault, distributing them
     * in proportion to the current holdings.
     * @dev Tokens deposited remain in the vault until the next
     * rebalance and are not utilized for liquidity on Pearl.
     * @param amount0Desired Maximum amount of token0 to deposit
     * @param amount1Desired Maximum amount of token1 to deposit
     * @param to Recipient of shares
     * @param amount0Min Reverts if the resulting amount0 is less than this
     * @param amount1Min Reverts if the resulting amount1 is less than this
     * @return shares Number of shares minted
     * @return amount0 Amount of token0 deposited
     * @return amount1 Amount of token1 deposited
     */
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address to,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 shares, uint256 amount0, uint256 amount1);

    /**
     * @notice Withdraws tokens in proportion to the vault's holdings.
     * @param shares Shares burned by sender
     * @param amount0Min Revert if resulting `amount0` is smaller than this
     * @param amount1Min Revert if resulting `amount1` is smaller than this
     * @param to Recipient of tokens
     * @return amount0 Amount of token0 sent to recipient
     * @return amount1 Amount of token1 sent to recipient
     */
    function withdraw(
        uint256 shares,
        address to,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1);

    /** @notice Add Liquidity in the pool
     * @dev only manager can add liquidity in case of rebalancing scenarios
     * @param tickLower lower limit of the position
     * @param tickUpper upper limit of the position
     * @param amount0  amount in token0 to be added in the pool
     * @param amount1  amount in token1 to be added in the pool
     * @param amount0Min minimum amount in token0 to be added in the pool
     * @param amount1Min minimum amount in token1 to be added in the pool
     */
    function addLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external;

    /**
     * @notice Updates alm box's positions.
     * @dev Three orders are placed - a full-range order, a base order and a
     * base order. The full-range order is placed first. Then the base
     * order is placed with as much remaining liquidity as possible. This order
     * should use up all of one token, leaving only the other one. This excess
     * amount is then placed as a single-sided bid or ask order.
     * Currently only base order is enabled
     * @param baseLower lower limit of the position
     * @param baseUpper upper limit of the position
     * @param amount0MinBurn minimum amount in token0 to be pulled out from the pool
     * @param amount1MinBurn minimum amount in token1 to be pulled out from the pool
     * @param amount0MinMint minimum amount in token0 to be added in the pool
     * @param amount1MinMint minimum amount in token1 to be added in the pool
     */
    function rebalance(
        int24 baseLower,
        int24 baseUpper,
        uint256 amount0MinBurn,
        uint256 amount1MinBurn,
        uint256 amount0MinMint,
        uint256 amount1MinMint
    ) external;

    /**
     * @notice Updates vault's positions.
     * @dev Pull liquidity out from the pool
     * @param baseLower lower limit of the position
     * @param baseUpper upper limit of the position
     * @param shares quantity of the lp tokens
     * @param amount0Min minimum amount in token0 to be added in the pool
     * @param amount1Min minimum amount in token1 to be added in the pool
     */
    function pullLiquidity(
        int24 baseLower,
        int24 baseUpper,
        uint128 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external;

    /**
     * @notice Claims collected management fees and transfers them to the specified address.
     * @dev This function can only be called by the owner of the contract.
     * @param to The address to which the collected fees will be transferred.
     * @return collectedfees0 The amount of collected fees denominated in token0.
     * @return collectedfees1 The amount of collected fees denominated in token1.
     */
    function claimManagementFees(
        address to
    ) external returns (uint256, uint256);

    /**
     * @notice Claims collected user fees and transfers them to the user address.
     * @dev This function can only be called by anyone but the fees will be transferred to the owner.
     * @param to The address for which the fees will be collected.
     * @param to The address to which the collected fees will be transferred.
     * @return collectedfees0 The amount of collected fees denominated in token0.
     * @return collectedfees1 The amount of collected fees denominated in token1.
     */
    function claimFees(
        address from,
        address to
    ) external returns (uint256, uint256);

    // state variables

    function baseLower() external view returns (int24);

    function baseUpper() external view returns (int24);

    function tickSpacing() external view returns (int24);

    function lastTimestamp() external view returns (uint256);

    function fee() external view returns (uint24);

    function owner() external view returns (address);

    function token0() external view returns (IERC20Upgradeable);

    function token1() external view returns (IERC20Upgradeable);

    function max0() external view returns (uint256);

    function max1() external view returns (uint256);

    function maxTotalSupply() external view returns (uint256);

    /**
     * @notice Balance of token0 in vault not used in any position.
     * @dev token balance also has user and management fees.
     * fess must be deducted from balance of token
     */
    function getBalance0() external view returns (uint256);

    /**
     * @notice Balance of token1 in vault not used in any position.
     * @dev token balance also has user and management fees.
     * fess must be deducted from balance of token
     */
    function getBalance1() external view returns (uint256);

    // view functions

    /**
     * @notice Calculates the amounts of lqiuidity in the pool for each share.
     * @return liquidityPerShare The calculated liquidity of shares for the recipient.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getPoolLiquidityPerShare()
        external
        view
        returns (uint256 liquidityPerShare);

    /**
     * @notice Calculates the amounts of token0 and token1 using shares for a given recipient address.
     * @param shares The amount of shares
     * @return amount0 The calculated amount of token0 shares for the shares minus fee0.
     * @return amount1 The calculated amount of token1 shares for the shares minus fee0.
     * @return liquidity The calculated liquidity of shares.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getSharesAmount(
        uint256 shares
    )
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @notice Calculates the vault's total holdings of token0 and token1 - in
     * other words, how much of each token the vault would hold if it withdrew
     * all its liquidity from PearlV3.
     * @return total0 The total amount of token0 managed by the box minus the fee.
     * @return total1 The total amount of token1 managed by the box minus the fee.
     * @return pool0 The total amount of token0 deployed in the pool minus management fee.
     * @return pool1 The total amount of token1 deployed in the pool minus management fee.
     * @return liquidity The total liquidity deployed in the pool.
     */
    function getTotalAmounts()
        external
        view
        returns (
            uint256 total0,
            uint256 total1,
            uint256 pool0,
            uint256 pool1,
            uint128 liquidity
        );

    /// @notice Get the sqrt price before the given interval
    /// @param twapInterval Time intervals
    /// @return sqrtPriceX96 Sqrt price before interval
    function getSqrtTwapX96(
        uint32 twapInterval
    ) external view returns (uint160 sqrtPriceX96);

    function earnedFees(
        address account
    ) external view returns (uint256 amount0, uint256 amount1);
}
