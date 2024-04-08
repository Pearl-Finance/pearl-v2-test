// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title ILiquidBox
 * @dev Interface for the Trident contract, managing liquidity and rebalancing strategies on PearlV3.
 */
interface ILiquidBox {
    /**
     * @notice Initializes the Trident contract with initial parameters.
     * @param pool Address of the associated liquidity pool.
     * @param owner Address of the contract owner.
     * @param boxFactory Address of the factory creating the box.
     * @param name Name of the box.
     * @param symbol Symbol of the box.
     */
    function initialize(address pool, address owner, address boxFactory, string memory name, string memory symbol)
        external;

    /**
     * @notice Deposits tokens into the vault, distributing them in proportion to the current holdings.
     * @dev Tokens deposited remain in the vault until the next rebalance and are not utilized for liquidity on Pearl.
     * @param amount0Desired Maximum amount of token0 to deposit.
     * @param amount1Desired Maximum amount of token1 to deposit.
     * @param to Recipient of shares.
     * @param amount0Min Reverts if the resulting amount0 is less than this.
     * @param amount1Min Reverts if the resulting amount1 is less than this.
     * @return shares Number of shares minted.
     * @return amount0 Amount of token0 deposited.
     * @return amount1 Amount of token1 deposited.
     */
    function deposit(uint256 amount0Desired, uint256 amount1Desired, address to, uint256 amount0Min, uint256 amount1Min)
        external
        returns (uint256 shares, uint256 amount0, uint256 amount1);

    /**
     * @notice Withdraws tokens in proportion to the vault's holdings.
     * @param shares Shares burned by sender.
     * @param from The address for LP.
     * @param to Recipient of tokens.
     * @param amount0Min Revert if resulting `amount0` is smaller than this.
     * @param amount1Min Revert if resulting `amount1` is smaller than this.
     * @return amount0 Amount of token0 sent to recipient.
     * @return amount1 Amount of token1 sent to recipient.
     */
    function withdraw(uint256 shares, address from, address to, uint256 amount0Min, uint256 amount1Min)
        external
        returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Updates box's positions during rebalance.
     * @dev Currently, only the base order is enabled.
     * @param baseLower Lower limit of the position.
     * @param baseUpper Upper limit of the position.
     * @param amount0MinBurn Minimum amount in token0 to be pulled out from the pool.
     * @param amount1MinBurn Minimum amount in token1 to be pulled out from the pool.
     * @param amount0MinMint Minimum amount in token0 to be added to the pool.
     * @param amount1MinMint Minimum amount in token1 to be added to the pool.
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
     * @dev Pull liquidity out from the pool.
     * When the gauge is enabled, the total shares will be removed from the pool.
     * @param baseLower Lower limit of the position.
     * @param baseUpper Upper limit of the position.
     * @param shares Quantity of the LP tokens.
     * @param amount0Min Minimum amount in token0 to be added to the pool.
     * @param amount1Min Minimum amount in token1 to be added to the pool.
     */
    function pullLiquidity(int24 baseLower, int24 baseUpper, uint256 shares, uint256 amount0Min, uint256 amount1Min)
        external;

    /**
     * @notice Claims collected management fees and transfers them to the specified address.
     * @dev This function can only be called by the owner of the contract.
     * @param to The address to which the collected fees will be transferred.
     * @return collectedfees0 The amount of collected fees denominated in token0.
     * @return collectedfees1 The amount of collected fees denominated in token1.
     * @return collectedFeesOnEmission The amount of collected fees on reward emission from gauge.
     */
    function claimManagementFees(address to) external returns (uint256, uint256, uint256);

    /**
     * @notice Claims collected user fees and transfers them to the user address.
     * @dev This function can only be called by anyone but the fees will be transferred to the owner.
     * @param from The address for which the fees will be collected.
     * @param to The address to which the collected fees will be transferred.
     * @return collectedfees0 The amount of collected fees denominated in token0.
     * @return collectedfees1 The amount of collected fees denominated in token1.
     */
    function claimFees(address from, address to) external returns (uint256, uint256);

    // State variables

    /**
     * @notice Returns the lower limit of the base position.
     * @return The lower limit of the base position.
     */
    function baseLower() external view returns (int24);

    /**
     * @notice Returns the upper limit of the base position.
     * @return The upper limit of the base position.
     */
    function baseUpper() external view returns (int24);

    /**
     * @notice Returns the spacing between ticks in the position range.
     * @return The tick spacing in the position range.
     */
    function tickSpacing() external view returns (int24);

    /**
     * @notice Returns the timestamp of the last update.
     * @return timestamp timestamp of the last update.
     */
    function lastTimestamp() external view returns (uint256);

    /**
     * @notice Returns the fee associated with the box.
     * @return fee fee associated with the box.
     */
    function fee() external view returns (uint24);

    /**
     * @notice Returns the owner of the box.
     * @return owner address of the box owner.
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the ERC20 token0 associated with the box.
     * @return token0 ERC20 token0 associated with the box.
     */
    function token0() external view returns (IERC20Upgradeable);

    /**
     * @notice Returns the ERC20 token1 associated with the box.
     * @return token1 ERC20 token1 associated with the box.
     */
    function token1() external view returns (IERC20Upgradeable);

    /**
     * @notice Returns the maximum amount of token0 that can be held in the box.
     * @return max0 maximum amount of token0.
     */
    function max0() external view returns (uint256);

    /**
     * @notice Returns the maximum amount of token1 that can be held in the box.
     * @return max1 maximum amount of token1.
     */
    function max1() external view returns (uint256);

    /**
     * @notice Returns the maximum total supply of shares that can be minted.
     * @return maxTotalSupply maximum total supply of shares.
     */
    function maxTotalSupply() external view returns (uint256);

    /**
     * @notice Balance of token0 in vault not used in any position.
     * @dev Token balance also has user and management fees.
     * Fees must be deducted from the balance of the token.
     * @return balance0 balance of the token0.
     */
    function getBalance0() external view returns (uint256);

    /**
     * @notice Balance of token1 in vault not used in any position.
     * @dev Token balance also has user and management fees.
     * Fees must be deducted from the balance of the token.
     * @return balance1 balance of the token1.
     */
    function getBalance1() external view returns (uint256);

    // View functions
    /**
     * @notice Calculates the amounts of liquidity in the pool for each share.
     * @return liquidityPerShare The calculated liquidity of shares for the recipient.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getPoolLiquidityPerShare() external view returns (uint256 liquidityPerShare);

    /**
     * @notice Calculates the amounts of token0 and token1 using shares for a given recipient address.
     * @param shares The amount of shares.
     * @return amount0 The calculated amount of token0 shares for the shares minus fee0.
     * @return amount1 The calculated amount of token1 shares for the shares minus fee0.
     * @return liquidity The calculated liquidity of shares.
     * @dev This function is view-only and does not modify the state of the contract.
     */
    function getSharesAmount(uint256 shares)
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @notice Calculates the vault's total holdings of token0 and token1 - in
     * other words, how much of each token the vault would hold if it withdrew
     * all its liquidity from PearlV2.
     * @return total0 The total amount of token0 managed by the box minus the fee.
     * @return total1 The total amount of token1 managed by the box minus the fee.
     * @return pool0 The total amount of token0 deployed in the pool minus management fee.
     * @return pool1 The total amount of token1 deployed in the pool minus management fee.
     * @return liquidity The total liquidity deployed in the pool.
     */
    function getTotalAmounts()
        external
        view
        returns (uint256 total0, uint256 total1, uint256 pool0, uint256 pool1, uint128 liquidity);

    /// @notice Get the sqrt price before the given interval
    /// @param twapInterval Time intervals
    /// @return sqrtPriceX96 Current sqrt price
    /// @return sqrtPriceX96Twap Sqrt price before interval
    function getSqrtTwapX96(uint32 twapInterval)
        external
        view
        returns (uint160 sqrtPriceX96, uint160 sqrtPriceX96Twap);

    /**
     * @notice Returns the earned fees for a specific account.
     * @param account The address of the account.
     * @return amount0 The amount of earned fees denominated in token0.
     * @return amount1 The amount of earned fees denominated in token1.
     */
    function earnedFees(address account) external view returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Returns the management fees that can be claimed.
     * @return claimable0 The amount of claimable fees denominated in token0.
     * @return claimable1 The amount of claimable fees denominated in token1.
     * @return emission The collected amount of fees on reward emission from the gauge.
     */
    function getManagementFees() external view returns (uint256 claimable0, uint256 claimable1, uint256 emission);

    function getPoolParams() external view returns (address, address, uint24);

    /**
     * @notice Calculates the amounts for a given tick range using the input amounts
     * @param deposit0 The input amount of token0
     * @param deposit1 The input amount of token1
     * @return required0 The required amount of token0 for the current tick range
     * @return required1 The required amount of token1 for the current tick range
     */
    function getRequiredAmountsForInput(uint256 deposit0, uint256 deposit1)
        external
        view
        returns (uint256 required0, uint256 required1);

    function setMaxTotalSupply(uint256 _maxTotalSupply) external;

    function toggleDirectDeposit() external;

    function setOwner(address _owner) external;

    function setGauge(address _gauge) external;

    function setFee(uint24 newFee) external;
}
