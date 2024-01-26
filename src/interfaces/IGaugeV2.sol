// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./dex/INonfungiblePositionManager.sol";

interface IGaugeV2 is IERC721Receiver {
    /// @notice initialize the pool
    function initialize(
        address factory,
        address pool,
        address nonfungiblePositionManager,
        address rewardToken,
        address distribution,
        address internal_bribe,
        bool isForPair
    ) external;

    /** @notice Deposit NFT to stake in gauge for earning emissions.
     * @param tokenId NFT token id for staking in the gauge.
     */
    function deposit(uint256 tokenId) external;

    /** @notice Withdraw staked NFT from gauge
     * @param tokenId NFT token id for staking in the gauge.
     * @param to The address which should receive the nft.
     * @param data bytes data for the nft reciever method.
     * @param rewardOwed reward amount collected from staking NFT.
     */
    function withdraw(
        uint256 tokenId,
        address to,
        bytes memory data
    ) external returns (uint256 rewardOwed);

    /** @notice Increase the position liquidity
     * @dev user can increase the liquidity using token ID
     * @param params increase liquidity params dervied from INonfungiblePositionManager
     */
    function increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams calldata params
    ) external;

    /** @notice Decrease the position liquidity
     * @dev user can decrease the liquidity using token ID
     * @param params decrease liquidity params dervied from INonfungiblePositionManager
     */
    function decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external;

    /**
     * @notice notify the alm LP tokens deposit in the alm gauge
     * @dev Tokens deposited remain in the vault until unstaked
     * @param tickLower Minimum tick limit of the alm box
     * @param tickUpper Maximum tick limit of the alm box
     * @param liquidityDelta liquidity delta staked in the alm gauge
     */
    function notifyERC20Deposit(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta
    ) external;

    /**
     * @notice notify the alm LP tokens withdrawn from the alm gauge
     * @dev Tokens deposited remain in the vault until unstaked
     * @param tickLower Minimum tick limit of the alm box
     * @param tickUpper Maximum tick limit of the alm box
     * @param liquidityDelta liquidity delta un-staked from the alm gauge
     * @return rewardOwed amount of reward tranferred to the owner before unstaking
     */
    function notifyERC20Withdraw(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta
    ) external returns (uint256 rewardOwed);

    /**
     * @notice collect the rewards from the gauge
     * @dev Tokens deposited remain in the gauge until unstaked
     * @param tokenId nft tokenId for claiming the reward
     * @return rewardOwed amount of reward tranferred to the owner
     */
    function collectReward(
        uint256 tokenId
    ) external returns (uint256 rewardOwed);

    /**
     * @notice collect the rewards from the gauge accrued for ALM
     * @dev Tokens deposited remain in the gauge until unstaked
     * @param tickLower Minimum tick limit of the alm box
     * @param tickUpper Maximum tick limit of the alm box
     * @return rewardOwed amount of reward tranferred to the owner
     */
    function collectRewardForALM(
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 rewardOwed);

    /**
     * @notice collect the fees from the gauge
     * @dev fee is accrued from the alm and nft positions and
     * transferred to the bribe contract for distribution to voters
     * @return claimed0 fee amount collected in token0
     * @return claimed1 fee amount collected in token1
     */
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);

    /**
     * @notice notify reward amount from the distribution
     * @dev reward is distributed at each epoch based on voting weights
     * @param token The address of the reward token.
     * @param amount amount of the reward for the current epoch.
     */
    function notifyRewardAmount(address token, uint256 amount) external;

    /**
     * @notice check whether gauge is enabled for pair
     * @dev if enabled fee will be collected as internal bribe
     * @return bool status of the gauge
     */
    function isForPair() external returns (bool);

    /**
     * @notice notify reward amount from the distribution
     * @dev reward is distributed at each epoch based on voting weights
     * @param targetTick current tick value of the pool.
     * @param zeroForOne the direction of the swap.
     * @return bool for tick cross if liquidity was staked
     */
    function crossTo(int24 targetTick, bool zeroForOne) external returns (bool);

    function setDistribution(address distro) external;

    function setALMGauge(address gaugeALM) external;

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

    function balanceOf(address account) external view returns (uint256);

    function tokenOfOwnerByIndex(
        address owner,
        uint256 idx
    ) external view returns (uint256);

    function gaugeAlm() external view returns (address);

    /**
     * @notice Get the claimable reward for the given tokenId
     * @param owner address representing the owner
     * @param tokenId nft tokenId of the owner
     * @return amount amount of claimable reward in reward token
     */
    function getReward(
        address owner,
        uint256 tokenId
    ) external view returns (uint256 amount);

    /**
     * @notice Get the claimable reward for the ALM
     * @param tickLower lower range of the tick
     * @param tickUpper upper range of the tick
     * @return amount amount of claimable reward in reward token
     */
    function getRewardForALM(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 amount);

    /**
     * @notice Get the claimable fee for internal bribe distribution
     * @return amount0 amount of claimable fee in  token0
     * @return amount1 amount of claimable fee in  token1
     */
    function feeAmount()
        external
        view
        returns (uint256 amount0, uint256 amount1);
}
