// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "layerzerolabs/token/oft/v1/interfaces/IOFT.sol";

import {SafeCast} from "./libraries/SafeCast.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {FixedPoint128} from "./libraries/FixedPoint128.sol";
import {VirtualTick} from "./libraries/VirtualTick.sol";
import {TickBitmap} from "./libraries/TickBitmap.sol";
import {StakePosition} from "./libraries/StakePosition.sol";
import {TickMath} from "./libraries/TickMath.sol";

import "./interfaces/IBribe.sol";
import {IGaugeV2, IERC721Receiver} from "./interfaces/IGaugeV2.sol";
import "./interfaces/IGaugeV2Factory.sol";
import "./interfaces/dex/IPearlV2Factory.sol";
import "./interfaces/dex/IPearlV2Pool.sol";
import {INonfungiblePositionManager} from "./interfaces/dex/INonfungiblePositionManager.sol";
import "./Epoch.sol";

/**
 * @title GaugeV2 for Concentrated Liquidity Pools
 * @author Maverick
 * @notice This PearlV3 Gauge contract is designed for Concentrated Liquidity Pools and employs the
 * `secondsPerActiveLiquidity` metric to distribute rewards among liquidity providers.
 * Rewards are allocated based on the duration and amount of active liquidity provided by users.
 * The gauge monitors the time-weighted active liquidity, rewarding users in proportion to their
 * contribution, encouraging sustained and strategic liquidity provision.
 * Emissions are calculate using the amount of time the price is
 * within the LP's range (only active liquidity will get rewards), and
 * the concentration of liquidity (where concentrated liquidity will get more rewards).
 * Additionally, collected fees from staked LP tokens are distributed as internal bribes to incentivize voters
 * participating in governance or decision-making processes related to the liquidity management.
 * Liquidity providers earn rewards based on the duration and quantity of active liquidity they contribute,
 * while participants in governance receive internal bribes from collected fees.
 * For detailed function descriptions and reward distribution mechanisms, refer to protocol documentaion.
 */

contract GaugeV2 is
    IGaugeV2,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using StakePosition for mapping(bytes32 => StakePosition.Info);
    using StakePosition for StakePosition.Info;
    using VirtualTick for mapping(int24 => VirtualTick.Info);
    using TickBitmap for mapping(int16 => uint256);

    /************************************************
     *  NON UPGRADEABLE STORAGE
     ***********************************************/

    // accumulated rebalance in token0/token1 units
    struct FeeAmount {
        uint256 amount0;
        uint256 amount1;
    }

    struct NFTPositionInfo {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        address pool;
        int24 tick;
    }

    struct RewardsInfo {
        uint256 amount;
        uint256 disbursed;
        uint256 rewardRate;
        uint256 residueAmount;
        uint256 liquidity0rewards;
        uint256 periodFinish;
        uint256 lastUpdateTime;
    }

    //fix value as alm doesn't hold any NFT
    uint16 public constant ALM_TOKENID = 1409;
    uint256 public constant PRECISION = 10 ** 18;

    uint64 public nonce;
    bool public isForPair;
    bool public isMainChain;

    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    int24 public tickSpacing;
    int24 public globalTick;

    uint128 public gaugeLiquidity;
    uint128 public maxLiquidityPerTick;
    uint256 public rewardsGrowthGlobalX128;
    uint256 public totalStaked;
    uint256 public pendingReward;

    address public DISTRIBUTION;
    address public internal_bribe;
    address public override gaugeAlm;

    IERC20Upgradeable public _VE;
    IERC20Upgradeable public rewardToken;
    IPearlV2Pool public pool;
    IPearlV2Factory public factory;
    IGaugeV2Factory public gaugeFactory;
    INonfungiblePositionManager public nonfungiblePositionManager;

    FeeAmount public feeAmount;
    RewardsInfo public override rewardsInfo;

    //private staked owner data
    mapping(address owner => mapping(uint256 index => uint256))
        private _ownedTokens;
    mapping(uint256 tokenId => uint256) private _ownedTokensIndex;

    mapping(int24 => VirtualTick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    /// @dev stakes[owner, tickLower, tickUpper] => Stake
    mapping(bytes32 => StakePosition.Info) public stakepos;
    // mapping(uint256 => address) tokenIdToUser;

    mapping(address => uint256) public stakedBalance;
    mapping(uint64 => uint256) public rewardCredited;

    /************************************************
     *  EVENTS
     ***********************************************/

    event Deposit(address indexed user, uint256 tokenId, uint128 liquidity);
    event Withdraw(address indexed user, uint256 tokenId, uint128 liquidity);

    event IncreaseLiquidity(
        address indexed user,
        uint256 tokenId,
        uint128 liquidity
    );

    event DecreaseLiquidity(
        address indexed user,
        uint256 tokenId,
        uint128 liquidity
    );

    event Collect(
        address indexed user,
        uint256 tokenId,
        address recipient,
        uint256 rewardsOwed
    );

    event RewardBridged(address indexed gauge, uint256 reward);
    event RewardAdded(uint256 reward, uint256 residueAmount);
    event RewardCredited(uint64 nonceId, uint256 reward);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        bool _isMainChain,
        uint16 _lzMainChainId,
        uint16 _lzPoolChainId,
        address _factory,
        address _pool,
        address _nonfungiblePositionManager,
        address _rewardToken,
        address _distribution,
        address _internal_bribe,
        bool _isForPair
    ) public initializer {
        require(
            _factory != address(0) &&
                _pool != address(0) &&
                _rewardToken != address(0) &&
                _distribution != address(0) &&
                _internal_bribe != address(0) &&
                _nonfungiblePositionManager != address(0),
            "!zero address"
        );

        require(_lzMainChainId != 0 && _lzPoolChainId != 0, "!zero chain id");

        __Ownable_init();
        __ReentrancyGuard_init();

        isMainChain = _isMainChain;
        lzMainChainId = _lzMainChainId;
        lzPoolChainId = _lzPoolChainId;

        isForPair = _isForPair;
        gaugeFactory = IGaugeV2Factory(msg.sender);
        factory = IPearlV2Factory(_factory);
        pool = IPearlV2Pool(_pool);
        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
        rewardToken = IERC20Upgradeable(_rewardToken);

        DISTRIBUTION = _distribution; // distro address (voter)
        internal_bribe = _internal_bribe; // lp fees goes here

        // only allowed on pool chain
        if (
            (_isMainChain && _lzMainChainId == _lzPoolChainId) ||
            (!isMainChain && _lzMainChainId != _lzPoolChainId)
        ) {
            tickSpacing = pool.tickSpacing();
            maxLiquidityPerTick = VirtualTick.tickSpacingToMaxLiquidityPerTick(
                tickSpacing
            );
        }
    }

    //=======================  MODIFIERS  =========================================

    modifier isStakingAllowed() {
        //Allow staking if poolGauge address is zero address
        _checkStakingAllowed();
        _;
    }

    /// @notice Checks whether an address is gaugeALM or not
    modifier isGaugeAlm() {
        _checkGaugeALM();
        _;
    }

    /// @notice Checks whether an address is staker or not
    modifier onlyStaker(address owner, uint256 tokenId) {
        _checkStaker(owner, tokenId);
        _;
    }

    /// @notice Claim NFT fee for the tokenId
    /// @dev pulled fee is available as internal bribe
    modifier pullNFTFee(uint256 tokenId) {
        _pullNFTFee(tokenId);
        _;
    }

    //=======================  SET  =========================================

    /// @notice whitelist the gauge address
    function setALMGauge(address _gauge) external onlyOwner {
        require(_gauge != address(0));
        gaugeAlm = _gauge;
    }

    ///@notice set distribution address (should be GaugeProxyL2)
    function setDistribution(address _distribution) external onlyOwner {
        require(_distribution != address(0));
        DISTRIBUTION = _distribution;
    }

    //=======================  ACTION  =========================================

    /// @inheritdoc IGaugeV2
    function deposit(uint256 tokenId) external isStakingAllowed nonReentrant {
        // transfer NFT
        nonfungiblePositionManager.safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            ""
        );
        //check onERC721Received for furhter logic
    }

    /// @notice Upon receiving a Pearl V2 ERC721, creates the token deposit setting owner to `from`. Also stakes token
    /// in one or more incentives if properly formatted `data` has a length > 0.
    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override isStakingAllowed pullNFTFee(tokenId) returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), "NP");

        NFTPositionInfo memory info = _getPositionInfo(tokenId);
        require(info.liquidity != 0, "liquidity");

        _deposit(
            from,
            tokenId,
            info.tickLower,
            info.tickUpper,
            info.tick,
            info.liquidity
        );

        emit Deposit(from, tokenId, info.liquidity);
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IGaugeV2
    function withdraw(
        uint256 tokenId,
        address to,
        bytes memory data
    )
        external
        nonReentrant
        onlyStaker(msg.sender, tokenId)
        pullNFTFee(tokenId)
        returns (uint256 rewardsOwed)
    {
        require(to != address(0) && to != address(this));
        NFTPositionInfo memory info = _getPositionInfo(tokenId);

        rewardsOwed = _withdraw(
            msg.sender,
            tokenId,
            info.tickLower,
            info.tickUpper,
            info.tick,
            info.liquidity,
            true
        );

        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            to,
            tokenId,
            data
        );

        emit Withdraw(msg.sender, tokenId, info.liquidity);
    }
    /// @notice Increase the position liquidity
    /// @dev user can increase the liquidity using token ID
    /// @inheritdoc IGaugeV2
    function increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams calldata params
    )
        external
        nonReentrant
        onlyStaker(msg.sender, params.tokenId)
        pullNFTFee(params.tokenId)
    {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidityBefore,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(params.tokenId);

        //transfer tokens for the nonfungiblePositionManager's pearlV2MintCallback
        if (params.amount0Desired > 0) {
            IERC20Upgradeable(token0).safeIncreaseAllowance(
                address(nonfungiblePositionManager),
                params.amount0Desired
            );
            IERC20Upgradeable(token0).safeTransferFrom(
                msg.sender,
                address(this),
                params.amount0Desired
            );
        }

        if (params.amount1Desired > 0) {
            IERC20Upgradeable(token1).safeIncreaseAllowance(
                address(nonfungiblePositionManager),
                params.amount1Desired
            );
            IERC20Upgradeable(token1).safeTransferFrom(
                msg.sender,
                address(this),
                params.amount1Desired
            );
        }

        nonfungiblePositionManager.increaseLiquidity(params);
        NFTPositionInfo memory position = _getPositionInfo(params.tokenId);

        //net liquidity will always be positive as tokens are added in the pool
        uint128 netLiquidity = position.liquidity - liquidityBefore;

        //withdraw the liquity
        StakePosition.Info memory stakePosition = stakepos.get(
            msg.sender,
            params.tokenId
        );

        // Withdraw from the current position to claim rewards and
        // then re-enter the staking position with new liquidity.
        _updateLiquidity(params.tokenId, position, stakePosition);

        emit IncreaseLiquidity(msg.sender, params.tokenId, netLiquidity);
    }

    /// @notice Decrease the position liquidity
    /// @dev user can increase or decrease the liquidity using token ID
    /// @inheritdoc IGaugeV2
    function decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    )
        external
        nonReentrant
        onlyStaker(msg.sender, params.tokenId)
        pullNFTFee(params.tokenId)
    {
        nonfungiblePositionManager.decreaseLiquidity(params);
        NFTPositionInfo memory position = _getPositionInfo(params.tokenId);

        //withdraw the liquity
        StakePosition.Info memory stakePosition = stakepos.get(
            msg.sender,
            params.tokenId
        );

        // Execute an exit strategy to collect rewards and
        // subsequently re-enter the staking position with new liquidity.
        // Skip re-entry if the new liquidity is zero.
        _updateLiquidity(params.tokenId, position, stakePosition);

        // Only burned amount will be collected at this point as
        // all the fees were collected in the begining
        nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: params.tokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit DecreaseLiquidity(msg.sender, params.tokenId, params.liquidity);
    }

    // ====== ALM ERC20 ========

    /// @inheritdoc IGaugeV2
    function notifyERC20Deposit(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta
    ) external override nonReentrant isGaugeAlm isStakingAllowed {
        require(liquidityDelta > 0, "LQ");
        (, int24 tick, , , , , ) = pool.slot0();

        _deposit(
            msg.sender,
            ALM_TOKENID,
            tickLower,
            tickUpper,
            tick,
            liquidityDelta
        );

        emit IncreaseLiquidity(msg.sender, ALM_TOKENID, liquidityDelta);
    }

    /// @inheritdoc IGaugeV2
    function notifyERC20Withdraw(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta
    ) external override nonReentrant isGaugeAlm returns (uint256 rewardsOwed) {
        require(liquidityDelta > 0, "LQ");
        (, int24 tick, , , , , ) = pool.slot0();

        rewardsOwed = _withdraw(
            msg.sender,
            ALM_TOKENID,
            tickLower,
            tickUpper,
            tick,
            liquidityDelta,
            true
        );

        emit DecreaseLiquidity(msg.sender, ALM_TOKENID, liquidityDelta);
    }

    /// @notice collect emission for token ID
    /// @inheritdoc IGaugeV2
    function collectReward(
        uint256 tokenId
    )
        external
        nonReentrant
        onlyStaker(msg.sender, tokenId)
        pullNFTFee(tokenId)
        returns (uint256 rewardsOwed)
    {
        NFTPositionInfo memory nftInfo = _getPositionInfo(tokenId);
        rewardsOwed = _collectReward(
            tokenId,
            msg.sender,
            nftInfo.tickLower,
            nftInfo.tickUpper,
            true
        );
        emit Collect(msg.sender, tokenId, msg.sender, rewardsOwed);
    }

    /// @notice collect emission for alm gauge
    function collectRewardForALM(
        int24 tickLower,
        int24 tickUpper
    ) external nonReentrant isGaugeAlm returns (uint256 rewardsOwed) {
        rewardsOwed = _collectReward(
            ALM_TOKENID,
            msg.sender,
            tickLower,
            tickUpper,
            true
        );
        emit Collect(msg.sender, ALM_TOKENID, msg.sender, rewardsOwed);
    }

    /// @notice Transitions to next tick when notified from the pool
    /// @dev The set of active ticks in the gauge must be a subset of the active ticks in the real pool
    /// @inheritdoc IGaugeV2
    function crossTo(
        int24 targetTick,
        bool zeroForOne
    ) external nonReentrant returns (bool) {
        require(address(pool) == msg.sender, "pool");
        _distributeRewards();

        int24 tickNext;
        bool initialized;

        int24 _globalTick = globalTick;
        uint128 _liquidity = gaugeLiquidity;
        uint256 _rewardsGrowthGlobalX128 = rewardsGrowthGlobalX128;

        bool isTrue = zeroForOne
            ? _globalTick != TickMath.MIN_TICK
            : _globalTick != TickMath.MAX_TICK - 1;

        // // The set of active ticks in the gauge must be a subset of the active ticks in the pool
        // // so this loop will cross no more ticks than the pool
        while (isTrue) {
            (tickNext, initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                    _globalTick,
                    tickSpacing,
                    zeroForOne
                );

            if ((zeroForOne ? targetTick >= tickNext : targetTick < tickNext))
                break;
            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (tickNext < TickMath.MIN_TICK) {
                tickNext = TickMath.MIN_TICK;
            } else if (tickNext > TickMath.MAX_TICK) {
                tickNext = TickMath.MAX_TICK;
            }

            // if the tick is initialized, run the tick transition
            if (initialized) {
                int128 liquidityNet = ticks.cross(
                    tickNext,
                    _rewardsGrowthGlobalX128
                );

                // if we're moving leftward, we interpret liquidityNet as the opposite sign
                // safe because liquidityNet cannot be type(int128).min
                unchecked {
                    if (zeroForOne) liquidityNet = -liquidityNet;
                }

                _liquidity = liquidityNet < 0
                    ? _liquidity - uint128(-liquidityNet)
                    : _liquidity + uint128(liquidityNet);
            }

            unchecked {
                _globalTick = zeroForOne ? tickNext - 1 : tickNext;
            }
        }
        globalTick = targetTick;
        // update liquidity if it is updated
        if (gaugeLiquidity != _liquidity) gaugeLiquidity = _liquidity;
        return true;
    }

    /**
     * @notice Notifies the contract of the reward amount to update the reward rate.
     * @dev Receives rewards from distribution and adjusts the reward rate.
     * Emissions can only be distributed from the main chain to the pool chain.
     * If the pool is deployed on the other chain, then bridge the emission to the pool chain.
     * @inheritdoc IGaugeV2
     * @param token Address of the reward token.
     * @param reward Amount of rewards to be acknowledged.
     */
    function notifyRewardAmount(
        address token,
        uint256 reward
    ) external override nonReentrant {
        //emissions can only be distributed from main chain to pool chain
        // transfer the emisison if pool is not deployed on main chain
        require(msg.sender == DISTRIBUTION, "!distribution");
        require(token == address(rewardToken), "!reward token");

        //if pool is deployed on main chain
        if (isMainChain && (lzMainChainId == lzPoolChainId)) {
            //update the epoch reward
            _updateEpochReward(reward);
        } else {
            // record the reward for distribution to pool chain gauge
            rewardToken.safeTransferFrom(DISTRIBUTION, address(this), reward);
            pendingReward += reward;
            emit RewardAdded(reward, 0);
        }
    }

    /**
     * @dev PendingReward can only recieved on main chain to be distributed to
     * pool chain gauge using the LayerZero OFT cross chain transfer
     * @inheritdoc IGaugeV2
     */
    function bridgeReward() external payable override nonReentrant {
        require(pendingReward > 0, "!pending");

        uint256 reward = pendingReward;
        pendingReward = 0; //reset reward

        uint256 dstChainId = lzPoolChainId;
        address dstAddress = gaugeFactory.getTrustedRemoteAddress(
            uint16(dstChainId),
            address(this)
        );

        IOFT(address(rewardToken)).sendFrom{value: msg.value}(
            address(this),
            uint16(dstChainId),
            abi.encodePacked(dstAddress),
            reward,
            payable(msg.sender),
            address(0),
            bytes("")
        );
        emit RewardBridged(dstAddress, reward);
    }

    /**
     * @notice Notifies the contract of credited rewards from a source chain.
     * @dev Rewards can only be credited by the main chain gauge to the pool gauge deployed on the satellite chain.
     * 200000K gas limit on OFT token transfers.
     * @param srcChainId Source chain ID.
     * @param initiator Address of the bribe contract on the source chain.
     *
     * @param token Address of the reward token.
     * @param reward Amount of rewards to be credited.
     */
    function notifyCredit(
        uint16 srcChainId,
        address initiator,
        address,
        address token,
        uint256 reward
    ) external nonReentrant {
        // Recieve emissions only on the pool chain from main chain
        require(
            !isMainChain && (srcChainId == lzMainChainId),
            "not allowed on main chain"
        );

        require(
            msg.sender == address(rewardToken) && token == address(rewardToken),
            "!reward token"
        );

        address remoteAddress = gaugeFactory.getTrustedRemoteAddress(
            srcChainId,
            address(this)
        );

        require(initiator == remoteAddress, "not remote caller");
        nonce += 1;

        rewardCredited[nonce] = reward;
        emit RewardCredited(nonce, reward);
    }

    /**
     * @notice Acknowledges the reward credited from the main chain.
     * @dev Rewards can only be credited by the main chain gauge to the pool gauge deployed on the satellite chain.
     * @param _nonce nonce for the reward
     */
    function ackReward(uint64 _nonce) external nonReentrant {
        uint256 _reward = rewardCredited[_nonce];
        require(_reward > 0, "!reward");

        rewardCredited[_nonce] = 0;

        //update the epoch reward
        _updateEpochReward(_reward);
    }

    /// @inheritdoc IGaugeV2
    function claimFees() external returns (uint256 claimed0, uint256 claimed1) {
        if (internal_bribe == address(0)) {
            return (0, 0);
        }

        address _token0 = pool.token0();
        address _token1 = pool.token1();

        //Re-used IGaugeV2 interface just for claiming fees
        (claimed0, claimed1) = IGaugeV2(gaugeAlm).claimFees();

        claimed0 += feeAmount.amount0;
        claimed1 += feeAmount.amount1;

        if (claimed0 > 0) {
            feeAmount.amount0 = 0;
            IERC20Upgradeable(_token0).safeIncreaseAllowance(
                internal_bribe,
                claimed0
            );
            IBribe(internal_bribe).notifyRewardAmount(_token0, claimed0);
        }

        if (claimed1 > 0) {
            feeAmount.amount1 = 0;
            IERC20Upgradeable(_token1).safeIncreaseAllowance(
                internal_bribe,
                claimed1
            );
            IBribe(internal_bribe).notifyRewardAmount(_token1, claimed1);
        }
        emit ClaimFees(msg.sender, claimed0, claimed1);
    }

    /// @notice poke the positions to claim fee
    /// @dev redeem fee fopr the inactive positions fee to be distributed to bribe contract
    function poke(
        uint256[] memory tokenIds
    ) external onlyOwner isStakingAllowed {
        for (uint8 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            //check if token is staked
            if (_ownedTokensIndex[id] == 0) continue;
            _pullNFTFee(id);
        }
    }

    //============================== PURE ==================================

    function min256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    //============================== INTERNAL ==================================

    function _checkStakingAllowed() internal view {
        // Enables staking either on the main chain with the same layer-zero chain ID
        // or gauges created on satellite chains.
        require(
            (isMainChain && lzMainChainId == lzPoolChainId) || !isMainChain,
            "!staking"
        );
    }

    function _checkStaker(address owner, uint256 tokenId) internal view {
        _checkStakingAllowed();
        StakePosition.Info memory stakeInfo = stakepos.get(owner, tokenId);
        require(
            nonfungiblePositionManager.ownerOf(tokenId) == address(this) &&
                stakeInfo.owner == owner,
            "staker"
        );
    }

    function _checkGaugeALM() internal view {
        require(msg.sender == gaugeAlm, "gauge");
    }

    function _updateEpochReward(uint256 reward) internal {
        //distribute the reward for the time detla
        _distributeRewards();

        uint256 epoch = EPOCH_DURATION;

        // transfer token only for main chain pools, tokens are already recieved
        // for the satellite chain pool gauge
        if (isMainChain) {
            rewardToken.safeTransferFrom(DISTRIBUTION, address(this), reward);
        }

        //collect dust left from the reward distribution
        uint256 residueAmount = rewardsInfo.amount - rewardsInfo.disbursed;

        // Add residue rewards collected for Zero liquidity
        if (rewardsInfo.liquidity0rewards > 0) {
            residueAmount += rewardsInfo.liquidity0rewards;
            //reset the zero liquidity reward amount
            rewardsInfo.liquidity0rewards = 0;
        }

        rewardsInfo.amount = reward + residueAmount;
        rewardsInfo.residueAmount = residueAmount;

        //calculate new reward rate for current epoch
        rewardsInfo.rewardRate = FullMath.mulDiv(reward, PRECISION, epoch);

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardToken.balanceOf(address(this));
        require(
            rewardsInfo.rewardRate <=
                FullMath.mulDiv(balance, PRECISION, epoch),
            "Provided reward too high"
        );

        //reset the disbursed amount to zero
        rewardsInfo.disbursed = 0;
        rewardsInfo.lastUpdateTime = block.timestamp;
        rewardsInfo.periodFinish = block.timestamp + epoch;
        emit RewardAdded(reward, residueAmount);
    }

    function _deposit(
        address owner,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        int24 tick,
        uint128 liquidityDelta
    ) internal {
        StakePosition.Info storage stake = _updatePoolPosition(
            owner,
            tokenId,
            tickLower,
            tickUpper,
            tick,
            int128(liquidityDelta)
        );

        // if liquidity was ZERO update stake position and user token mappings
        // skip increase liquidity from gaugeALM
        if (stake.liquidity == liquidityDelta) {
            //update ownership
            stake.owner = owner;
            stake.rewardsGrowthInsideLastX128 = _getInnerRewardGrowth(
                tickLower,
                tickUpper
            );

            //Update user nft mappings
            stakedBalance[owner] += 1;
            _addToken(owner, tokenId);
        }
    }

    function _withdraw(
        address owner,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        int24 tick,
        uint128 liquidityDelta,
        bool isUnstake
    ) internal returns (uint256 rewardsOwed) {
        //collect reward
        rewardsOwed = _collectReward(
            tokenId,
            owner,
            tickLower,
            tickUpper,
            true
        );

        //zero update for reward collection
        StakePosition.Info storage stake = _updatePoolPosition(
            owner,
            tokenId,
            tickLower,
            tickUpper,
            tick,
            -int128(liquidityDelta)
        );

        //update stake position and user token mappings
        if (stake.liquidity == 0) {
            stake.rewardsGrowthInsideLastX128 = 0;
            // reset the stake position when lqiuidity is unstaked
            if (isUnstake) {
                stake.owner = address(0);
                //update nft tracking
                stakedBalance[owner] -= 1;
                _removeToken(owner, tokenId);
            }
        }
    }

    function _updateLiquidity(
        uint256 tokenId,
        NFTPositionInfo memory position,
        StakePosition.Info memory stakePosition
    ) internal {
        // Withdraw from the position to claim rewards.
        // when new liquidity is zero or the staked position already has liquidity.
        if (position.liquidity == 0 || stakePosition.liquidity != 0) {
            _withdraw(
                msg.sender,
                tokenId,
                position.tickLower,
                position.tickUpper,
                position.tick,
                stakePosition.liquidity,
                false //not unstaking
            );
        }

        if (position.liquidity != 0) {
            //re-enter the stake position with new liquidity
            _deposit(
                msg.sender,
                tokenId,
                position.tickLower,
                position.tickUpper,
                position.tick,
                position.liquidity
            );
        }
    }

    /// @dev Gets and updates a position with the given liquidity delta
    /// @param owner owner of the position
    /// @param tickLower the lower tick of the position's tick range
    /// @param tickUpper the upper tick of the position's tick range
    /// @param tick the current tick, passed to avoid sloads
    function _updatePoolPosition(
        address owner,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        int24 tick,
        int128 liquidityDelta
    ) internal returns (StakePosition.Info storage stake) {
        globalTick = tick;

        bool flippedLower;
        bool flippedUpper;

        //distribute rewards and collect reards for current liquidity
        _distributeRewards();

        if (liquidityDelta != 0) {
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                rewardsGrowthGlobalX128,
                false,
                maxLiquidityPerTick
            );

            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                rewardsGrowthGlobalX128,
                true,
                maxLiquidityPerTick
            );

            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }

            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }

            if (liquidityDelta < 0) {
                if (flippedLower) {
                    ticks.clear(tickLower);
                }
                if (flippedUpper) {
                    ticks.clear(tickUpper);
                }
            }

            //if tick lies is in range then update the global liquidity delta
            if (tick >= tickLower && tick < tickUpper) {
                uint128 liquidityBefore = gaugeLiquidity; // SLOAD for gas optimization
                gaugeLiquidity = liquidityDelta < 0
                    ? liquidityBefore - uint128(-liquidityDelta)
                    : liquidityBefore + uint128(liquidityDelta);
            }
        }

        //update stake position
        stake = stakepos.get(owner, tokenId);
        stake.update(liquidityDelta);
    }

    function _getPositionInfo(
        uint256 tokenId
    ) internal view returns (NFTPositionInfo memory info) {
        (
            ,
            ,
            info.token0,
            info.token1,
            info.fee,
            info.tickLower,
            info.tickUpper,
            info.liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);
        info.pool = factory.getPool(info.token0, info.token1, info.fee);
        (, info.tick, , , , , ) = pool.slot0();
        require(info.pool == address(pool));
    }

    function _getInnerRewardGrowth(
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 rewardsGrowthInsideLastX128) {
        unchecked {
            RewardsInfo memory _info = rewardsInfo;
            uint256 _rewardsGrowthGlobalX128 = rewardsGrowthGlobalX128;

            //check if epoch period is finished
            if (_info.periodFinish > _info.lastUpdateTime) {
                uint256 timeDelta = (
                    (min256(block.timestamp, _info.periodFinish) -
                        _info.lastUpdateTime)
                );
                uint256 _liquidity = gaugeLiquidity;
                if (timeDelta > 0 && _liquidity > 0) {
                    uint256 rewards = FullMath.mulDiv(
                        _info.rewardRate,
                        timeDelta,
                        PRECISION
                    );
                    _rewardsGrowthGlobalX128 += FullMath.mulDiv(
                        rewards,
                        FixedPoint128.Q128,
                        _liquidity
                    );
                }
            }

            rewardsGrowthInsideLastX128 = ticks.getrewardsGrowthInside(
                tickLower,
                tickUpper,
                globalTick,
                _rewardsGrowthGlobalX128
            );
        }
    }

    function _getLatestReward(
        int24 tickLower,
        int24 tickUpper,
        StakePosition.Info memory stake
    )
        internal
        view
        returns (uint256 reward, uint256 rewardsGrowthInsideLastX128)
    {
        rewardsGrowthInsideLastX128 = _getInnerRewardGrowth(
            tickLower,
            tickUpper
        );
        reward = FullMath.mulDiv(
            rewardsGrowthInsideLastX128 - stake.rewardsGrowthInsideLastX128,
            stake.liquidity,
            FixedPoint128.Q128
        );
    }

    function _pullNFTFee(uint256 tokenId) internal {
        unchecked {
            (uint256 fee0, uint256 fee1) = nonfungiblePositionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            if (fee0 > 0) feeAmount.amount0 += fee0;
            if (fee1 > 0) feeAmount.amount1 += fee1;
        }
    }

    function _distributeRewards() internal {
        RewardsInfo memory _info = rewardsInfo;
        if (_info.periodFinish < _info.lastUpdateTime) return; // no distribution after epoch end

        uint256 timeDelta = (
            (min256(block.timestamp, _info.periodFinish) - _info.lastUpdateTime)
        );

        if (timeDelta == 0) return; // only once per block

        uint256 _liquidity = gaugeLiquidity;
        uint256 rewards = FullMath.mulDiv(
            _info.rewardRate,
            timeDelta,
            PRECISION
        );

        if (_liquidity > 0) {
            rewardsGrowthGlobalX128 += FullMath.mulDiv(
                rewards,
                FixedPoint128.Q128,
                gaugeLiquidity
            );
        } else {
            rewardsInfo.liquidity0rewards += rewards;
        }
        rewardsInfo.disbursed += rewards;
        rewardsInfo.lastUpdateTime = block.timestamp;
    }

    function _collectReward(
        uint256 tokenId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bool isTransfer
    ) internal returns (uint256 rewardsOwed) {
        _distributeRewards();
        StakePosition.Info memory stakeInfo = stakepos.get(owner, tokenId);
        uint256 rewardsGrowthInsideLastX128;
        (rewardsOwed, rewardsGrowthInsideLastX128) = _getLatestReward(
            tickLower,
            tickUpper,
            stakeInfo
        );

        StakePosition.Info storage stake = stakepos.get(msg.sender, tokenId);

        stake.rewardsGrowthInsideLastX128 = rewardsGrowthInsideLastX128;

        if (isTransfer && rewardsOwed > 0) {
            rewardsOwed += stake.rewardsOwed;
            stake.rewardsOwed = 0;
            rewardToken.safeTransfer(msg.sender, rewardsOwed);
        } else {
            stake.rewardsOwed += rewardsOwed;
        }
    }

    /**
     * @dev Private function to add a token to this ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addToken(address to, uint256 tokenId) private {
        uint256 length = stakedBalance[to] - 1;
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to remove a token from this ownership-tracking data structures.
     * This has O(1) time complexity, but alters the order of the __ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeToken(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex = stakedBalance[from];
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    //============================== VIEW ==================================

    /**
     * @notice Get the claimable reward for the given tokenId
     * @param owner address representing the owner
     * @param tokenId nft tokenId of the owner
     * @return amount amount of claimable reward in reward token
     */
    function getReward(
        address owner,
        uint256 tokenId
    ) public view returns (uint256 amount) {
        StakePosition.Info memory stake = stakepos.get(owner, tokenId);
        amount = stake.rewardsOwed;
        if (stake.liquidity != 0) {
            NFTPositionInfo memory nftInfo = _getPositionInfo(tokenId);
            (uint256 rewardsOwed, ) = _getLatestReward(
                nftInfo.tickLower,
                nftInfo.tickUpper,
                stake
            );
            amount += rewardsOwed;
        }
    }

    /**
     * @notice Get the claimable reward for the ALM
     * @param tickLower lower range of the tick
     * @param tickUpper upper range of the tick
     * @return amount amount of claimable reward in reward token
     */
    function getRewardForALM(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 amount) {
        StakePosition.Info memory stake = stakepos.get(gaugeAlm, ALM_TOKENID);
        amount = stake.rewardsOwed;
        if (stake.liquidity != 0) {
            (uint256 rewardsOwed, ) = _getLatestReward(
                tickLower,
                tickUpper,
                stake
            );
            amount += rewardsOwed;
        }
    }

    /**
     * @dev Return the amount of staked nft.
     * @param owner address representing the owner
     * @return amount quantity of nft staked by the owner
     */
    function balanceOf(address owner) public view returns (uint256) {
        return stakedBalance[owner];
    }

    /**
     * @dev Get token id for
     * @param owner address representing the owner
     * @param idx index opf the _ownedTokens mappings
     * @return tokenId tokenId mapped on the give index to repsective owner
     */
    function tokenOfOwnerByIndex(
        address owner,
        uint256 idx
    ) external view returns (uint256) {
        if (idx >= balanceOf(owner)) {
            revert("NA");
        }
        return _ownedTokens[owner][idx];
    }
}
