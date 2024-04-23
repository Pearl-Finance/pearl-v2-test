// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Voter} from "../../src/Voter.sol";
import {GaugeV2} from "../../src/GaugeV2.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Bribe} from "../../src/v1.5/Bribe.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OFTMockToken} from ".././utils/OFTMockToken.sol";
import {console2 as console} from "forge-std/Test.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";
import {IGaugeV2ALM} from "../../src/interfaces/IGaugeV2ALM.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../../src/interfaces/dex/ISwapRouter.sol";
import {IVotingEscrow} from "../../src/interfaces/IVotingEscrow.sol";
import {IPearlV2Pool} from "../../src/interfaces/dex/IPearlV2Pool.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LiquidityAmounts} from "../../src/libraries/LiquidityAmounts.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {IEpochController} from "../../src/interfaces/IEpochController.sol";
import {IPearlV2Factory} from "../../src/interfaces/dex/IPearlV2Factory.sol";
import {FixedPoint128} from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import {MathUpgradeable} from "openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/dex/INonfungiblePositionManager.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    ISwapRouter router;
    Voter public voter;

    GaugeV2 public gauge;
    IMinter public minter;

    AddressSet internal _actors;
    OFTMockToken public nativeOFT;
    IEpochController public epochController;

    struct FeeAmount {
        uint256 amount0;
        uint256 amount1;
    }

    mapping(address => uint256) ids;
    mapping(address => bool) hasVoted;

    mapping(bytes32 => uint256) public calls;
    mapping(address => uint256) public ghost_usersVotes;

    mapping(address => uint256) public ghost_amount0Fee;
    mapping(address => uint256) public ghost_amount1Fee;

    mapping(address => uint256) public ghost_gaugesRewards;
    mapping(address => FeeAmount) public ghost_internalBribeBalance;

    mapping(address => mapping(uint256 => address)) public gaugeNftOwner;
    mapping(address => mapping(address => uint256)) public nftOwnerInGauge;
    mapping(address => mapping(address => uint256)) public ghost_userLiquidity;

    bool firstTime;

    address ve;
    address pool;
    address[] pools;

    address currentActor;
    address boxCurrentActor;

    address lzEndPointMockL1;
    uint256 public ghost_zeroVote;

    uint256 public ghost_zeroVotes;
    uint256 public ghost_mintedSum;

    uint256 public ghost_usersVote;
    uint256 public ghost_veNftCount;

    uint256 public ghost_actualVote;
    uint256 public ghost_actualMint;

    uint256 public ghost_actualSwap;
    uint256 public ghost_rebaseRewards;

    uint256 public ghost_teamEmissions;
    address nonfungiblePositionManager;

    uint256 public ghost_tokenIdIsZero;
    uint256 public ghost_actualDeposit;

    uint256 public ghost_actualWithdraw;
    uint256 public ghost_actualDistribute;

    uint256 public ghost_totalGaugesRewards;
    uint256 public ghost_actualDecreaseLiquidity;

    uint256 public ghost_actualIncreaseLiquidity;
    uint256 public ghost_tokenIdOrLiquidityIsZero;

    uint256 public ghost_idsIsNotZeroOrZeroAddress;
    uint256 public ghost_tokenIdIsZeroOrIsContract;

    uint256 public ghost_zeroAmountOrDistributionInProgress;
    uint256 public ghost_addressOrLiquidityToRemoveOrTokenIdIsZero;

    int24 tickLower = 6931;
    int24 tickUpper = 27081;

    uint256 rebaseMax = 5_00;
    uint256 rebaseSlope = 625;

    uint256 public teamRate = 25;
    uint256 public emission = 990;

    uint256 weekly = 2_600_000 * 10 ** 18;
    uint256 public constant PRECISION = 1_000;

    constructor(
        Voter _voter,
        address _ve,
        address _nativeOFT,
        address _router,
        address _epochController,
        address _lzEndPointMockL1,
        address _nonfungiblePositionManager,
        address[] memory _pools
    ) {
        ve = _ve;
        voter = _voter;
        pools = _pools;
        router = ISwapRouter(_router);
        minter = IMinter(voter.minter());
        nativeOFT = OFTMockToken(_nativeOFT);
        lzEndPointMockL1 = _lzEndPointMockL1;
        epochController = IEpochController(_epochController);
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(currentActor);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function deposit(uint256 poolID) external createActor countCall("Deposit") {
        bool isContract = currentActor.code.length > 0;
        poolID = bound(poolID, 0, pools.length - 1);

        address gauge_ = voter.gauges(pools[poolID]);

        if (nftOwnerInGauge[currentActor][gauge_] == 0 && !isContract) {
            ghost_actualDeposit++;
            vm.startPrank(currentActor);
            (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, pools[poolID], currentActor);
            vm.stopPrank();

            _swapInternally(0.5 ether, poolID);
            _poke(poolID, tokenId);

            vm.startPrank(currentActor);
            IERC721(nonfungiblePositionManager).approve(gauge_, tokenId);

            GaugeV2(payable(gauge_)).deposit(tokenId);
            ghost_userLiquidity[currentActor][gauge_] = liquidityToAdd;

            nftOwnerInGauge[currentActor][gauge_] = tokenId;
            gaugeNftOwner[gauge_][tokenId] = currentActor;

            vm.stopPrank();
        } else {
            ghost_tokenIdIsZeroOrIsContract++;
        }
    }

    function claimFeesInGauge(uint256 poolID) external countCall("Claim Fees In Gauge") {
        poolID = bound(poolID, 0, pools.length - 1);
        address gauge_ = voter.gauges(pools[poolID]);

        address internalBribes = voter.internal_bribes(gauge_);
        (uint256 claimed0, uint256 claimed1) = GaugeV2(payable(gauge_)).claimFees();

        ghost_internalBribeBalance[internalBribes].amount0 =
            ghost_internalBribeBalance[internalBribes].amount0 + claimed0;

        ghost_internalBribeBalance[internalBribes].amount1 =
            ghost_internalBribeBalance[internalBribes].amount1 + claimed1;

        ghost_amount0Fee[pools[poolID]] = ghost_amount0Fee[pools[poolID]] - claimed0;
        ghost_amount1Fee[pools[poolID]] = ghost_amount1Fee[pools[poolID]] - claimed1;
    }

    function mintNFT(uint256 amount, uint256 duration, uint256 actorSeed)
        public
        useActor(actorSeed)
        countCall("Mint")
    {
        if (ids[currentActor] == 0 && currentActor != address(0)) {
            ghost_actualMint++;

            amount = bound(amount, 0, type(uint8).max);
            duration = bound(amount, 2 weeks, 2 * 52 weeks);

            if (amount != 0 && !IEpochController(epochController).checkDistribution()) {
                if (amount < 1e18) amount = amount * 1e18;

                ghost_actualMint++;
                ghost_mintedSum += amount;

                __mint(currentActor, amount);
                vm.startPrank(currentActor);
                nativeOFT.approve(address(ve), amount);

                (bool success0, bytes memory data) = address(ve).call(
                    abi.encodeWithSignature("mint(address,uint256,uint256)", currentActor, amount, duration)
                );

                ghost_veNftCount++;
                assert(success0);
                uint256 id = abi.decode(data, (uint256));

                ids[currentActor] = id;
                vm.stopPrank();
            } else {
                ghost_zeroAmountOrDistributionInProgress++;
            }
        } else {
            ghost_idsIsNotZeroOrZeroAddress++;
        }
    }

    function swap(uint128 amountIn, uint256 poolID) external {
        _swap(amountIn, poolID, false);
    }

    function vote(uint256 actorSeed, uint256 poolID) public useActor(actorSeed) countCall("Vote") {
        uint256 weight = 1;
        poolID = bound(poolID, 0, pools.length - 1);

        address[] memory _poolVote = new address[](1);
        _poolVote[0] = pools[poolID];

        uint256[] memory _weights = new uint256[](1);
        _weights[0] = weight;

        address gauge_ = voter.gauges(pools[poolID]);
        Bribe b = Bribe(voter.external_bribes(address(gauge_)));

        uint256 vote = IVotingEscrow(ve).getVotes(currentActor);
        uint256 previousBalance = b.balanceOf(currentActor);

        if (vote > 0) {
            ghost_actualVote++;
            vm.startPrank(currentActor);
            voter.vote(_poolVote, _weights);
            vm.stopPrank();

            if (hasVoted[currentActor]) {
                _userVotes(currentActor, previousBalance, true, b, pools[poolID]);
            } else {
                _userVotes(currentActor, 0, false, b, pools[poolID]);
            }

            hasVoted[currentActor] = true;
        } else {
            ghost_zeroVote++;
        }
    }

    function distribute() external countCall("Distribute") {
        if (ghost_usersVote > 0) {
            ghost_actualDistribute++;
            uint256 _weekly;

            if (!firstTime) {
                _weekly = weekly;
                firstTime = true;
            } else {
                weekly = _weeklyEmission();
                _weekly = weekly;
            }

            uint256 _rebase = _calculateRebase(_weekly);
            uint256 _teamEmissions = (_weekly * teamRate) / PRECISION;
            uint256 gaugesReward = _weekly - _rebase - _teamEmissions;

            uint256 _ratio = (gaugesReward * 1e18) / voter.totalWeight();
            uint256 index = voter.index();
            index += _ratio;
            gaugesReward = _updateFor(index);

            ghost_rebaseRewards += _rebase;
            ghost_teamEmissions += _teamEmissions;
            ghost_totalGaugesRewards += gaugesReward;

            vm.warp(block.timestamp + minter.nextPeriod());
            epochController.distribute();

            if (IEpochController(epochController).checkDistribution()) {
                // finish distribution
                while (IEpochController(epochController).checkDistribution()) {
                    epochController.distribute();
                }
            }
        } else {
            ghost_zeroVotes++;
        }
    }

    // function claimEmission() external useActor(actorSeed) countCall("Claim Emission") {
    //     for (uint256 i = 0; i < pools.length; i++) {
    //         address gauge_ = voter.gauges(pools[poolID]);
    //         uint256 rewardsOwed = GaugeV2(payable(gauge_)).collectReward(tokenId);
    //     }
    // }

    function withdraw(uint128 liquidityToRemove, uint256 actorSeed, uint256 poolID)
        external
        useActor(actorSeed)
        countCall("Withdraw")
    {
        poolID = bound(poolID, 0, pools.length - 1);
        address payable gauge_ = payable(voter.gauges(pools[poolID]));

        uint256 tokenID = nftOwnerInGauge[currentActor][gauge_];
        (, uint128 liquidity,,) = GaugeV2(gauge_).stakePos(keccak256(abi.encodePacked(currentActor, tokenID)));

        if (tokenID != 0 && liquidity != 0) {
            ghost_actualWithdraw++;
            nftOwnerInGauge[currentActor][gauge_] = 0;

            _swapInternally(0.5 ether, poolID);
            _poke(poolID, tokenID);

            vm.startPrank(currentActor);
            GaugeV2(gauge_).withdraw(tokenID, currentActor, "0x");

            ghost_userLiquidity[currentActor][gauge_] = ghost_userLiquidity[currentActor][gauge_] - liquidity;
            vm.stopPrank();
        } else {
            ghost_tokenIdOrLiquidityIsZero++;
        }
    }

    function increaseLiquidity(uint256 actorSeed, uint256 poolID)
        external
        useActor(actorSeed)
        countCall("Increase Liquidity")
    {
        poolID = bound(poolID, 0, pools.length - 1);
        address payable gauge_ = payable(voter.gauges(pools[poolID]));
        uint256 tokenID = nftOwnerInGauge[currentActor][gauge_];

        if (tokenID != 0) {
            ghost_actualIncreaseLiquidity++;
            address token0 = IPearlV2Pool(pools[poolID]).token0();
            address token1 = IPearlV2Pool(pools[poolID]).token1();

            deal(address(token0), currentActor, 1 ether);
            deal(address(token1), currentActor, 1 ether);

            (uint160 sqrtRatioX96,,,,,,) = IPearlV2Pool(pools[poolID]).slot0();

            uint128 liquid = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                1 ether,
                1 ether
            );

            _swapInternally(0.5 ether, poolID);
            _poke(poolID, tokenID);

            vm.startPrank(gaugeNftOwner[gauge_][tokenID]);

            IERC20(token0).approve(gauge_, 1 ether);
            IERC20(token1).approve(gauge_, 1 ether);

            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                tokenId: tokenID,
                amount0Desired: 1 ether,
                amount1Desired: 1 ether,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

            (, uint128 liquidityBeforeTx,,) =
                GaugeV2(gauge_).stakePos(keccak256(abi.encodePacked(currentActor, tokenID)));

            GaugeV2(gauge_).increaseLiquidity(params);
            vm.stopPrank();

            (, uint128 liquidityAfterTx,,) =
                GaugeV2(gauge_).stakePos(keccak256(abi.encodePacked(currentActor, tokenID)));

            uint128 liquidityAdded = liquidityAfterTx - liquidityBeforeTx;
            ghost_userLiquidity[currentActor][gauge_] = ghost_userLiquidity[currentActor][gauge_] + liquidityAdded;
        } else {
            ghost_tokenIdIsZero++;
        }
    }

    function decreaseLiquidity(uint256 liquidityToRemove, uint256 actorSeed, uint256 poolID)
        public
        useActor(actorSeed)
        countCall("decrease Liquidity")
    {
        poolID = bound(poolID, 0, pools.length - 1);
        address gauge_ = voter.gauges(pools[poolID]);

        liquidityToRemove = bound(liquidityToRemove, 0, ghost_userLiquidity[currentActor][gauge_]);
        uint256 tokenID = nftOwnerInGauge[currentActor][gauge_];

        if (currentActor != address(0) && liquidityToRemove != 0 && tokenID != 0) {
            ghost_actualDecreaseLiquidity++;
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                tokenId: tokenID,
                liquidity: uint128(liquidityToRemove),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

            _swapInternally(0.5 ether, poolID);
            _poke(poolID, tokenID);

            vm.startPrank(currentActor);
            GaugeV2(payable(gauge_)).decreaseLiquidity(params);
            ghost_userLiquidity[currentActor][gauge_] = ghost_userLiquidity[currentActor][gauge_] - liquidityToRemove;
            vm.stopPrank();
        } else {
            ghost_addressOrLiquidityToRemoveOrTokenIdIsZero++;
        }
    }

    function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd, address _pool, address user)
        public
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address token0 = IPearlV2Pool(_pool).token0();
        address token1 = IPearlV2Pool(_pool).token1();

        deal(address(token0), user, amount0ToAdd);
        deal(address(token1), user, amount1ToAdd);

        IERC20(token0).approve(nonfungiblePositionManager, amount0ToAdd);
        IERC20(token1).approve(nonfungiblePositionManager, amount1ToAdd);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 100,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0ToAdd,
            amount1Desired: amount1ToAdd,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
    }

    // function bridgePendingRewardToL2() external countCall("bridgePendingRewardToL2") {
    //
    // }

    function reduceActors(uint256 acc, function(uint256, address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function callSummary() external view {
        console.log("-------------------");
        console.log("  ");
        console.log("Call summary:");
        console.log("  ");
        console.log("-------------------");
        console.log("Call Count:");
        console.log("-------------------");
        console.log("Swap(s)", calls["Swap"]);
        console.log("Vote(s)", calls["Vote"]);
        console.log("MintNFT(s):", calls["Mint"]);
        console.log("Deposit(s)", calls["Deposit"]);
        console.log("Withdraw(s)", calls["Withdraw"]);
        console.log("Distribute(s)", calls["Distribute"]);
        console.log("Decrease Liquidity(s)", calls["decrease Liquidity"]);
        console.log("Increase Liquidity(s)", calls["Increase Liquidity"]);
        console.log("Claim Fees In Gauge(s)", calls["Claim Fees In Gauge"]);
        console.log("-------------------");
        console.log("Zero Calls:");
        console.log("-------------------");
        console.log("Vote(s):", ghost_zeroVote);
        console.log("Distribute(s)", ghost_zeroVotes);
        console.log("Increase Liquidity(s):", ghost_tokenIdIsZero);
        console.log("Deposit(s):", ghost_tokenIdIsZeroOrIsContract);
        console.log("MintNFT(s):", ghost_idsIsNotZeroOrZeroAddress);
        console.log("Withdraw(s):", ghost_tokenIdOrLiquidityIsZero);
        console.log("MintNFT(s):", ghost_zeroAmountOrDistributionInProgress);
        console.log("Decrease Liquidity(s):", ghost_addressOrLiquidityToRemoveOrTokenIdIsZero);
        console.log("-------------------");
        console.log("Actual Calls:");
        console.log("-------------------");
        console.log("Swap(s)", ghost_actualSwap);
        console.log("Vote(s)", ghost_actualVote);
        console.log("MintNFT(s):", ghost_actualMint);
        console.log("Deposit(s)", ghost_actualDeposit);
        console.log("Withdraw(s)", ghost_actualWithdraw);
        console.log("Distribute(s)", ghost_actualDistribute);
        console.log("Decrease Liquidity(s)", ghost_actualDecreaseLiquidity);
        console.log("Increase Liquidity(s)", ghost_actualIncreaseLiquidity);
        console.log("Claim Fees In Gauge(s)", calls["Claim Fees In Gauge"]);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function __mint(address addr, uint256 amount) internal {
        vm.startPrank(address(11));
        (bool success,) = address(nativeOFT).call(abi.encodeWithSignature("mint(address,uint256)", addr, amount));
        assert(success);
        vm.stopPrank();
    }

    function _weeklyEmission() internal view returns (uint256) {
        uint256 calculate_emission = (weekly * emission) / PRECISION;
        uint256 circulating_supply = nativeOFT.totalSupply() - nativeOFT.balanceOf(ve);
        circulating_supply = (circulating_supply * 2) / PRECISION;
        return MathUpgradeable.max(circulating_supply, calculate_emission);
    }

    function _calculateRebase(uint256 _weeklyMint) internal view returns (uint256) {
        uint256 _veTotal = nativeOFT.balanceOf(address(ve));
        uint256 _pearlTotal = nativeOFT.totalSupply();

        uint256 lockedShare = (_veTotal * rebaseSlope) / _pearlTotal;
        if (lockedShare >= rebaseMax) {
            lockedShare = rebaseMax;
        }

        return (_weeklyMint * lockedShare) / PRECISION;
    }

    function _updateFor(uint256 index) internal returns (uint256 _share) {
        for (uint256 i = 0; i < pools.length; i++) {
            address gauge_ = voter.gauges(pools[i]);
            uint256 _supplied = voter.weights(pools[i]);

            if (_supplied != 0) {
                uint256 _supplyIndex = voter.supplyIndex(address(gauge_));
                uint256 _delta = index - _supplyIndex;

                if (_delta != 0) {
                    uint256 reward = (_supplied * _delta) / 1e18;
                    _share += reward;
                    ghost_gaugesRewards[gauge_] += reward;
                }
            }
        }
    }

    function _userVotes(address actor, uint256 previousBalance, bool voted, Bribe b, address votePool) internal {
        if (voted) {
            ghost_usersVote -= previousBalance;
            ghost_usersVote += b.balanceOf(actor);

            ghost_usersVotes[votePool] -= previousBalance;
            ghost_usersVotes[votePool] += b.balanceOf(actor);
        } else {
            ghost_usersVote += b.balanceOf(actor);
            ghost_usersVotes[votePool] += b.balanceOf(actor);
        }
    }

    function _getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        internal
        pure
        returns (uint256 quoteAmount)
    {
        unchecked {
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
            // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
            if (sqrtRatioX96 <= type(uint128).max) {
                uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                    : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
            } else {
                uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                    : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
            }
        }
    }

    function _swapInternally(uint128 amountIn, uint256 poolID) internal {
        _swap(amountIn, poolID, true);
    }

    function _swap(uint128 amountIn, uint256 poolID, bool internalCall) internal countCall("Swap") {
        if (!internalCall) {
            poolID = bound(poolID, 0, pools.length - 1);
            amountIn = uint128(bound(amountIn, 0, 1e18));
        }

        if (amountIn > 0) {
            if (amountIn < 1e9) amountIn = amountIn * 1e18;

            address token0 = IPearlV2Pool(pools[poolID]).token0();
            address token1 = IPearlV2Pool(pools[poolID]).token1();
            uint24 poolFee = IPearlV2Pool(pools[poolID]).fee();

            (, int24 tick,,,,,) = IPearlV2Pool(pools[poolID]).slot0();

            address tokenIn;
            address tokenOut;

            // if (inOut) {
            tokenIn = token1;
            tokenOut = token0;
            uint256 amountOut = _getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);

            if (IERC20(tokenOut).balanceOf(pools[poolID]) > amountOut) {
                ghost_actualSwap++;
                deal(token1, msg.sender, amountIn);

                vm.startPrank(msg.sender);
                IERC20(tokenIn).approve(address(router), amountIn);

                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: poolFee,
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

                router.exactInputSingle(params);
                vm.stopPrank();
            }
        }
    }

    function _poke(uint256 poolID, uint256 tokenId) internal {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 liquidity,
            uint256 userfeeGrowthInside0LastX128,
            uint256 userfeeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = INonfungiblePositionManager(nonfungiblePositionManager).positions(tokenId);

        vm.startPrank(nonfungiblePositionManager);
        IPearlV2Pool(pools[poolID]).burn(tickLower, tickUpper, 0);
        vm.stopPrank();

        bytes32 positionKey = keccak256(abi.encodePacked(address(nonfungiblePositionManager), tickLower, tickUpper));

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) =
            IPearlV2Pool(pools[poolID]).positions(positionKey);

        tokensOwed0 += uint128(
            FullMath.mulDiv(feeGrowthInside0LastX128 - userfeeGrowthInside0LastX128, liquidity, FixedPoint128.Q128)
        );

        tokensOwed1 += uint128(
            FullMath.mulDiv(feeGrowthInside1LastX128 - userfeeGrowthInside1LastX128, liquidity, FixedPoint128.Q128)
        );

        ghost_amount0Fee[pools[poolID]] = ghost_amount0Fee[pools[poolID]] + tokensOwed0;
        ghost_amount1Fee[pools[poolID]] = ghost_amount1Fee[pools[poolID]] + tokensOwed1;
    }

    function testExcluded() public {}
}
