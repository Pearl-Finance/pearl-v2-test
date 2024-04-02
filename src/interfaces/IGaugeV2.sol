// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./dex/INonfungiblePositionManager.sol";

/**
 * @title IGaugeV2
 * @notice Interface for version 2 of a Gauge contract used for staking NFTs and earning rewards.
 * @dev This interface extends the IERC721Receiver interface and defines additional functions for interacting with a Gauge contract.
 */
interface IGaugeV2 is IERC721Receiver {
    /**
     * @notice Initializes the gauge with the provided parameters.
     * @param isMainChain bool for main chain
     * @param lzMainChainId The layerzero ChainId of the main chain.
     * @param lzPoolChainId The layerzero ChainId of the pool.
     * @param factory The address of the factory contract.
     * @param pool The address of the pool contract.
     * @param nonfungiblePositionManager The address of the Nonfungible Position Manager contract.
     * @param rewardToken The address of the reward token.
     * @param distribution The address of the distribution contract.
     * @param internal_bribe The address of the internal bribe contract.
     * @param isForPair Boolean indicating if the gauge is enabled for a specific pair.
     */
    function initialize(
        bool isMainChain,
        uint16 lzMainChainId,
        uint16 lzPoolChainId,
        address factory,
        address pool,
        address nonfungiblePositionManager,
        address rewardToken,
        address distribution,
        address internal_bribe,
        bool isForPair
    ) external;

    /**
     * @notice Deposits an NFT token into the gauge for staking and earning emissions.
     * @param tokenId The ID of the NFT token to stake in the gauge.
     */
    function deposit(uint256 tokenId) external;

    /**
     * @notice Withdraws a staked NFT token from the gauge.
     * @param tokenId The ID of the NFT token to withdraw.
     * @param to The address to which the NFT token should be transferred.
     * @param data Bytes data for the NFT receiver method.
     * @return rewardOwed The amount of reward collected from staking the NFT.
     */
    function withdraw(
        uint256 tokenId,
        address to,
        bytes memory data
    ) external returns (uint256 rewardOwed);

    /**
     * @notice Increases the liquidity of the position.
     * @param params Parameters for increasing liquidity derived from INonfungiblePositionManager.
     */
    function increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams calldata params
    ) external payable;

    /**
     * @notice Decreases the liquidity of the position.
     * @param params Parameters for decreasing liquidity derived from INonfungiblePositionManager.
     */
    function decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external;

    /**
     * @notice Notifies the deposit of ALM LP tokens in the gauge.
     * @param tickLower The minimum tick limit of the ALM box.
     * @param tickUpper The maximum tick limit of the ALM box.
     * @param liquidityDelta The liquidity delta staked in the gauge.
     */
    function notifyERC20Deposit(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta
    ) external;

    /**
     * @notice Notifies the withdrawal of ALM LP tokens from the gauge.
     * @param tickLower The minimum tick limit of the ALM box.
     * @param tickUpper The maximum tick limit of the ALM box.
     * @param liquidityDelta The liquidity delta unstaked from the gauge.
     * @return rewardOwed The amount of reward transferred to the owner before unstaking.
     */
    function notifyERC20Withdraw(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta
    ) external returns (uint256 rewardOwed);

    /**
     * @notice Collects rewards from the gauge.
     * @param tokenId The NFT tokenId for claiming the reward.
     * @return rewardOwed The amount of reward transferred to the owner.
     */
    function collectReward(
        uint256 tokenId
    ) external returns (uint256 rewardOwed);

    /**
     * @notice Collects rewards from the gauge accrued for ALM.
     * @param tickLower The minimum tick limit of the ALM box.
     * @param tickUpper The maximum tick limit of the ALM box.
     * @return rewardOwed The amount of reward transferred to the owner.
     */
    function collectRewardForALM(
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 rewardOwed);

    /**
     * @notice Claims fees from the gauge.
     * @return claimed0 The amount of fee collected in token0.
     * @return claimed1 The amount of fee collected in token1.
     */
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);

    /**
     * @notice Notifies the contract of the reward amount to update the reward rate.
     * @dev Receives rewards from distribution and adjusts the reward rate.
     * Emissions can only be distributed from the main chain to the pool chain.
     * If the pool is deployed on the other chain, then bridge the emission to the pool chain.
     * @param token Address of the reward token.
     * @param reward Amount of rewards to be acknowledged.
     */
    function notifyRewardAmount(address token, uint256 reward) external;

    /**
     * @notice Bridge reward amount to the pool chain gauge.
     * @dev PendingReward can only recieved on main chain to be distributed to
     * pool chain gauge using the LayerZero OFT cross chain transfer
     */
    function bridgeReward() external payable;

    /**
     * @notice Checks whether the gauge is enabled for a specific pair.
     * @return status The status of the gauge.
     */
    function isForPair() external returns (bool);

    /**
     * @notice Checks whether the gauge pool is deployed on mainchain.
     * @return status The status of the pool mainChainId.
     */
    function isMainChain() external returns (bool);

    /**
     * @notice Notifies about tick cross for pool swap.
     * @dev This function can be only be called from the pool swap method.
     * @param targetTick The current tick value of the pool.
     * @param zeroForOne The direction of the swap.
     * @return tickCross Whether the liquidity was staked for a tick cross.
     */
    function crossTo(int24 targetTick, bool zeroForOne) external returns (bool);

    /**
     * @notice Sets the distribution contract address.
     * @param distro The address of the distribution contract.
     */
    function setDistribution(address distro) external;

    /**
     * @notice Sets the ALM gauge contract address.
     * @param gaugeALM The address of the ALM gauge contract.
     */
    function setALMGauge(address gaugeALM) external;

    /**
     * @notice Retrieves information about rewards.
     * @return amount The total amount of rewards.
     * @return disbursed The total amount of rewards disbursed.
     * @return rewardRate The rate at which rewards are distributed per second.
     * @return residueAmount The remaining amount of unclaimed rewards.
     * @return liquidity0rewards The amount of rewards allocated to liquidity providers.
     * @return periodFinish The timestamp when the current reward period ends.
     * @return lastUpdateTime The timestamp of the last update.
     */
    function rewardsInfo()
        external
        view
        returns (
            uint256 amount,
            uint256 disbursed,
            uint256 rewardRate,
            uint256 residueAmount,
            uint256 liquidity0rewards,
            uint256 periodFinish,
            uint256 lastUpdateTime
        );

    /**
     * @notice Retrieves the balance of NFT tokens owned by an account.
     * @param account The address of the account.
     * @return The balance of NFT tokens owned by the account.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Retrieves the NFT token ID of an owner by index.
     * @param owner The address of the owner.
     * @param idx The index of the NFT token.
     * @return The NFT token ID.
     */
    function tokenOfOwnerByIndex(
        address owner,
        uint256 idx
    ) external view returns (uint256);

    /**
     * @notice Retrieves the address of the ALM gauge contract.
     * @return The address of the ALM gauge contract.
     */
    function gaugeAlm() external view returns (address);

    /**
     * @notice Gets the claimable reward for the given tokenId.
     * @param owner The address of the owner.
     * @param tokenId The NFT tokenId.
     * @return amount The amount of claimable reward in the reward token.
     */
    function getReward(
        address owner,
        uint256 tokenId
    ) external view returns (uint256 amount);

    /**
     * @notice Gets the claimable reward for ALM.
     * @param tickLower The lower range of the tick.
     * @param tickUpper The upper range of the tick.
     * @return amount The amount of claimable reward in the reward token.
     */
    function getRewardForALM(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 amount);

    /**
     * @notice Gets the claimable fee for internal bribe distribution.
     * @return amount0 The amount of claimable fee in token0.
     * @return amount1 The amount of claimable fee in token1.
     */
    function feeAmount()
        external
        view
        returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Gets the reward amount pending for bridging to pool chain
     */
    function pendingReward() external view returns (uint256 reward);
}
