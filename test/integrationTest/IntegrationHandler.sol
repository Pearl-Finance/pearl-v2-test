// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Voter} from "../../src/Voter.sol";
import {GaugeV2} from "../../src/GaugeV2.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Bribe} from "../../src/v1.5/Bribe.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OFTMockToken} from ".././OFTMockToken.sol";
import {TestERC20} from "../../src/mock/TestERC20.sol";
import {console2 as console} from "forge-std/Test.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";
import {IVotingEscrow} from "../../src/interfaces/IVotingEscrow.sol";
import {IEpochController} from "../../src/interfaces/IEpochController.sol";
import {IPearlV2Factory} from "../../src/interfaces/dex/IPearlV2Factory.sol";
import {IPearlV2Pool} from "../../src/interfaces/dex/IPearlV2Pool.sol";
import {IRewardsDistributor} from "../../src/interfaces/IRewardsDistributor.sol";
import {MathUpgradeable} from "openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/dex/INonfungiblePositionManager.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {LiquidityAmounts} from "../../src/libraries/LiquidityAmounts.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    AddressSet internal _actors;

    TestERC20 public testERC20;
    TestERC20 public tokenX;
    OFTMockToken public nativeOFT;
    address public ve;
    Voter public voter;
    Bribe public bribe;
    GaugeV2 public gauge;
    IMinter public minter;
    IEpochController public epochController;
    IRewardsDistributor public rewardsDistributor;

    address pool;
    address[] pools;

    mapping(address => uint256) ids;
    mapping(address => bool) hasVoted;
    mapping(bytes32 => uint256) public calls;
    mapping(address => uint256) public ghost_usersVotes;
    mapping(address => uint256) public ghost_gaugesRewards;

    address nonfungiblePositionManager;
    address currentActor;
    address lzEndPointMockL1;

    uint256 public ghost_veNftCount;
    uint256 public ghost_zeroMint;
    uint256 public ghost_mintedSum;
    uint256 public ghost_actualMint;
    uint256 public ghost_usersVote;
    uint256 public ghost_rebaseRewards;
    uint256 public ghost_teamEmissions;
    uint256 public ghost_totalGaugesRewards;
    uint256 weekly = 2_600_000 * 10 ** 18;
    uint256 public emission = 990;
    uint256 public teamRate = 25;
    uint256 public constant PRECISION = 1_000;
    uint256 rebaseMax = 5_00;
    uint256 rebaseSlope = 625;

    constructor(
        Voter _voter,
        address _ve,
        address _nativeOFT,
        GaugeV2 _gauge,
        address _epochController,
        address _lzEndPointMockL1,
        address _nonfungiblePositionManager,
        address[] memory _pools
    ) {
        nativeOFT = OFTMockToken(_nativeOFT);
        ve = _ve;
        voter = _voter;
        gauge = _gauge;
        epochController = IEpochController(_epochController);
        bribe = Bribe(voter.external_bribes(address(gauge)));
        minter = IMinter(voter.minter());
        lzEndPointMockL1 = _lzEndPointMockL1;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        pools = _pools;
        rewardsDistributor = IRewardsDistributor(minter._rewards_distributor());
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

    mapping(uint256 => uint256) public amountLocked;
    mapping(address => uint256) public gaugeNftCount;
    mapping(address => mapping(uint256 => address)) public gaugeNftOwner;
    mapping(address => mapping(address => uint256)) public ghost_liquidityInGauge;
    mapping(address => mapping(address => uint256)) public nftOwnerInGauge;

    function deposit() external createActor countCall("Deposit") {
        vm.startPrank(currentActor);
        // poolID = bound(poolID, 0, pools.length - 1);

        address gauge_ = voter.gauges(pools[0]);

        if (nftOwnerInGauge[currentActor][gauge_] == 0) {
            (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, pools[0], currentActor);
            ghost_liquidityInGauge[currentActor][gauge_] = liquidityToAdd;

            IERC721(nonfungiblePositionManager).approve(gauge_, tokenId);
            GaugeV2(payable(gauge_)).deposit(tokenId);

            // gaugeNftCount[gauge_] == gaugeNftCount[gauge_] + 1;
            ghost_userLiquidity[currentActor][gauge_] = liquidityToAdd;
            nftOwnerInGauge[currentActor][gauge_] = tokenId;
            gaugeNftOwner[gauge_][tokenId] = currentActor;
            vm.stopPrank();
        }
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
                amountLocked[id] = IVotingEscrow(ve).getLockedAmount(id);

                ids[currentActor] = id;
                vm.stopPrank();
            } else {
                ghost_zeroMint++;
            }
        }
    }

    function vote(uint256 actorSeed, uint256 weight) public useActor(actorSeed) countCall("Vote") {
        weight = 1;
        // poolID = bound(poolID, 0, pools.length - 1);

        if (weight > 0) {
            address[] memory _poolVote = new address[](1);
            _poolVote[0] = pools[0];

            uint256[] memory _weights = new uint256[](1);
            _weights[0] = weight;

            address gauge_ = voter.gauges(pools[0]);
            Bribe b = Bribe(voter.external_bribes(address(gauge_)));

            uint256 vote = IVotingEscrow(ve).getVotes(currentActor);
            uint256 previousBalance = b.balanceOf(currentActor);

            if (vote > 0) {
                vm.startPrank(currentActor);
                voter.vote(_poolVote, _weights);
                vm.stopPrank();

                if (hasVoted[currentActor]) {
                    userVotes(currentActor, previousBalance, true, b, pools[0]);
                } else {
                    userVotes(currentActor, 0, false, b, pools[0]);
                }

                hasVoted[currentActor] = true;
            }
        }
    }

    bool firstTime;

    function distribute() external countCall("Distribute") {
        // if (ghost_usersVote > 0) {
        //     uint256 _weekly;

        //     if (!firstTime) {
        //         _weekly = weekly;
        //         firstTime = true;
        //     } else {
        //         weekly = weekly_emission();
        //         _weekly = weekly;
        //     }

        //     uint256 _rebase = calculate_rebase(_weekly);
        //     uint256 _teamEmissions = (_weekly * teamRate) / PRECISION;
        //     uint256 gaugesReward = _weekly - _rebase - _teamEmissions;

        //     uint256 _ratio = (gaugesReward * 1e18) / voter.totalWeight();
        //     uint256 index = voter.index();
        //     index += _ratio;
        //     gaugesReward = _updateFor(index);

        //     ghost_rebaseRewards += _rebase;
        //     ghost_teamEmissions += _teamEmissions;
        //     ghost_totalGaugesRewards += gaugesReward;

        //     vm.warp(block.timestamp + minter.nextPeriod());
        //     epochController.distribute();

        //     if (IEpochController(epochController).checkDistribution()) {
        //         // finish distribution
        //         while (IEpochController(epochController).checkDistribution()) {
        //             epochController.distribute();
        //         }
        //     }
        // }
    }

    // function claimDistributionRewards(uint256 tokenID) external {
    //     // tokenID = bound(tokenID, 0, ghost_veNftCount);
    //     // if (tokenID != 0) {
    //     //     uint256 claimable = rewardsDistributor.claimable(tokenID);

    //     //     if (claimable > 0) {
    //     //         currentActor = IVotingEscrow(ve).ownerOf(tokenID);
    //     //         vm.startPrank(currentActor);

    //     //         uint256 bal = IVotingEscrow(ve).getLockedAmount(tokenID);
    //     //         amountLocked[tokenID] -= IVotingEscrow(ve).getLockedAmount(tokenID);

    //     //         rewardsDistributor.claim(tokenID);

    //     //         uint256 balAfterTx = IVotingEscrow(ve).getLockedAmount(tokenID);
    //     //         uint256 diff = balAfterTx - bal;

    //     //         ghost_rebaseRewards -= diff;
    //     //         vm.stopPrank();
    //     //     }
    //     // }
    // }

    // function claimEmission() external useActor(actorSeed) countCall("Claim Emission") {
    //     for (uint256 i = 0; i < pools.length; i++) {
    //         address gauge_ = voter.gauges(pools[poolID]);
    //         uint256 rewardsOwed = GaugeV2(payable(gauge_)).collectReward(tokenId);
    //     }
    // }

    function withdraw(uint128 liquidityToRemove, uint256 actorSeed)
        external
        useActor(actorSeed)
        countCall("Withdraw")
    {
        address payable gauge_ = payable(voter.gauges(pools[0]));
        uint256 tokenID = nftOwnerInGauge[currentActor][gauge_];
        (, uint128 liquidity,,) = GaugeV2(gauge_).stakePos(keccak256(abi.encodePacked(currentActor, tokenID)));

        if (tokenID != 0 && liquidity != 0) {
            vm.startPrank(currentActor);
            nftOwnerInGauge[currentActor][gauge_] = 0;
            GaugeV2(gauge_).withdraw(tokenID, currentActor, "0x");
            ghost_userLiquidity[currentActor][gauge_] = ghost_userLiquidity[currentActor][gauge_] - liquidity;
            vm.stopPrank();
        }
    }

    function increaseLiquidity(uint256 actorSeed) external useActor(actorSeed) countCall("Increase Liquidity") {
        // poolID = bound(poolID, 0, pools.length - 1);
        // address
        address payable gauge_ = payable(voter.gauges(pools[0]));
        uint256 tokenID = nftOwnerInGauge[currentActor][gauge_];
        // bound(tokenID, 0, gaugeNftCount[gauge_]);

        if (tokenID != 0) {
            // currentActor = gaugeNftOwner[gauge_][tokenID];
            address token0 = IPearlV2Pool(pools[0]).token0();
            address token1 = IPearlV2Pool(pools[0]).token1();

            vm.startPrank(gaugeNftOwner[gauge_][tokenID]);
            // ghost_liquidityInGauge[currentActor][gauge_] = ghost_liquidityInGauge[currentActor][gauge_] + liquidityToAdd;

            deal(address(token0), currentActor, 1 ether);
            deal(address(token1), currentActor, 1 ether);

            (uint160 sqrtRatioX96,,,,,,) = IPearlV2Pool(pools[0]).slot0();

            int24 tickLower = (-887272 / 1) * 1;
            int24 tickUpper = (887272 / 1) * 1;

            uint128 liquid = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                1 ether,
                1 ether
            );

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

            assert(liquidityAfterTx == ghost_userLiquidity[currentActor][gauge_]);
        }
    }

    mapping(address => mapping(address => uint256)) public ghost_userLiquidity;

    function decreaseLiquidity(uint256 liquidityToRemove, uint256 actorSeed)
        public
        useActor(actorSeed)
        countCall("decrease Liquidity")
    {
        address gauge_ = voter.gauges(pools[0]);
        liquidityToRemove = bound(liquidityToRemove, 0, ghost_userLiquidity[currentActor][gauge_]);
        uint256 tokenID = nftOwnerInGauge[currentActor][gauge_];

        if (currentActor != address(0) && liquidityToRemove != 0) {
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                tokenId: tokenID,
                liquidity: uint128(liquidityToRemove),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

            vm.startPrank(currentActor);
            GaugeV2(payable(gauge_)).decreaseLiquidity(params);
            ghost_userLiquidity[currentActor][gauge_] = ghost_userLiquidity[currentActor][gauge_] - liquidityToRemove;
            vm.stopPrank();
        }
    }

    function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd, address _pool, address user)
        private
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
            tickLower: (-887272 / 1) * 1,
            tickUpper: (887272 / 1) * 1,
            amount0Desired: amount0ToAdd,
            amount1Desired: amount1ToAdd,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
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

    function userVotes(address actor, uint256 previousBalance, bool voted, Bribe b, address votePool) internal {
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

    // function test_shouldBridgePendingRewardToL2() external {
    //     vote(poolL2);
    //     GaugeV2 gauge = GaugeV2(payable(voterL1.gauges(poolL2)));

    //     gaugeV2FactoryL1.setTrustedRemoteAddress(
    //         lzPoolChainId,
    //         address(gauge),
    //         address(gaugeV2L2)
    //     );
    //     gaugeV2FactoryL2.setTrustedRemoteAddress(
    //         lzMainChainId,
    //         address(gaugeV2L2),
    //         address(gauge)
    //     );
    //     console.log(address(gauge), address(nativeOFT));

    //     gaugeV2FactoryL1.setTrustedRemoteAddress(
    //         lzPoolChainId,
    //         address(nativeOFT),
    //         address(gaugeV2L2)
    //     );
    //     gaugeV2FactoryL2.setTrustedRemoteAddress(
    //         lzMainChainId,
    //         address(gaugeV2L2),
    //         address(gauge)
    //     );

    //     vm.warp(block.timestamp + minter.nextPeriod());
    //     epochController.distribute();
    //     uint64 nonce = gauge.nonce();
    //     assertEq(nonce, 0);

    //     assertEq(gauge.rewardCredited(nonce + 1), 0);

    //     assertEq(otherOFT.balanceOf(address(gaugeV2L2)), 0);
    //     gauge.bridgeReward{value: 1 ether}();

    //     // nonce = gaugeV2L2.nonce();
    //     // assertEq(nonce, 1);
    //     // console.log(gaugeV2L2.rewardCredited(nonce + 1));

    //     // assertEq(gaugeV2L2.rewardCredited(nonce + 1), otherOFT.balanceOf(address(gaugeV2L2)));

    //     // assertEq(gauge.pendingReward(), 0);

    //     // assertEq(nativeOFT.balanceOf(address(gauge)), 0);
    //     // assertGt(otherOFT.balanceOf(address(gaugeV2L2)), 0);
    // }

    function claim(uint256 actorSeed) public useActor(actorSeed) countCall("claim") {}

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
        console.log("Mint(s)", calls["mint"]);
        console.log("Claim(s)", calls["claim"]);
        console.log("Set Reward(s)", calls["set reward"]);
        console.log("-------------------");
        console.log("Zero Calls:");
        console.log("-------------------");
        console.log("Mint(s):", ghost_zeroMint);
        console.log("-------------------");
        console.log("-------------------");
        console.log("Actual Calls:");
        console.log("-------------------");
        console.log("Mint(s):", ghost_actualMint);
    }

    function __mint(address addr, uint256 amount) internal {
        vm.startPrank(address(11));
        (bool success,) = address(nativeOFT).call(abi.encodeWithSignature("mint(address,uint256)", addr, amount));
        assert(success);
        vm.stopPrank();
    }

    function weekly_emission() public view returns (uint256) {
        uint256 calculate_emission = (weekly * emission) / PRECISION;
        uint256 circulating_supply = nativeOFT.totalSupply() - nativeOFT.balanceOf(ve);
        circulating_supply = (circulating_supply * 2) / PRECISION;
        return MathUpgradeable.max(circulating_supply, calculate_emission);
    }

    function calculate_rebase(uint256 _weeklyMint) public view returns (uint256) {
        uint256 _veTotal = nativeOFT.balanceOf(address(ve));
        uint256 _pearlTotal = nativeOFT.totalSupply();

        uint256 lockedShare = (_veTotal * rebaseSlope) / _pearlTotal;
        if (lockedShare >= rebaseMax) {
            lockedShare = rebaseMax;
        }

        return (_weeklyMint * lockedShare) / PRECISION;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
