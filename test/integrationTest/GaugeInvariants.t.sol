// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "../utils/Imports.sol";
import {Handler} from "./GaugeHandler.sol";

contract GaugeInvariantTest is Imports {
    Handler public handler;

    function setUp() public {
        l1SetUp();
        uint256 numberOfAssets = bound(type(uint8).max, 0, 5); // set max to 5 to reduce loopping time

        for (uint256 i = 0; i < numberOfAssets; i++) {
            TestERC20 tokenX = new TestERC20();
            IPearlV2Pool _pool = IPearlV2Pool(pearlV2Factory.createPool(address(nativeOFT), address(tokenX), 100));

            liquidBoxFactory.setBoxManager(address(liquidBoxManager));
            address _box = liquidBoxFactory.createLiquidBox(_pool.token0(), _pool.token1(), _pool.fee(), "BX", "Box");

            pearlV2Factory.initializePoolPrice(address(_pool), TickMath.getSqrtRatioAtTick(23027));
            address gauge_ = voterL1.createGauge{value: 0.1 ether}(address(_pool), "0x");
            GaugeV2ALM alm = GaugeV2ALM(GaugeV2(payable(gauge_)).gaugeAlm());

            gauges.push(gauge_);
            pools.push(address(_pool));
            box.push(_box);
        }

        handler = new Handler(
            voterL1,
            address(votingEscrow),
            address(nativeOFT),
            router,
            address(epochController),
            address(lzEndPointMockL1),
            address(nonfungiblePositionManager),
            pools
        );

        for (uint256 i = 0; i < numberOfAssets; i++) {
            handler.mintNewPosition(1000 ether, 1000 ether, pools[i], address(handler));
        }

        console.log("simulating using:", numberOfAssets, "pools and gauges");

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.mintNFT.selector;
        selectors[2] = Handler.vote.selector;
        selectors[3] = Handler.distribute.selector;
        selectors[4] = Handler.increaseLiquidity.selector;
        selectors[5] = Handler.decreaseLiquidity.selector;
        selectors[6] = Handler.withdraw.selector;
        selectors[7] = Handler.swap.selector;
        selectors[8] = Handler.claimFeesInGauge.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));

        // l2();
        // vm.chainId(mainChainId);
    }

    function invariant_veNftCountIsSame() external {
        assertEq(votingEscrow.totalSupply(), handler.ghost_veNftCount());
    }

    function invariant_collectedFeeIsSameAsFeeAmountsInGauge() external {
        for (uint256 g; g < pools.length; ++g) {
            (uint256 amount0, uint256 amount1) = GaugeV2(payable(gauges[g])).feeAmount();

            assertEq(amount0, handler.ghost_amount0Fee(pools[g]));
            assertEq(amount1, handler.ghost_amount1Fee(pools[g]));
        }
    }

    function invariant_claimedFeeToInternalBribeIsSame() external {
        for (uint256 g; g < gauges.length; ++g) {
            address internalBribe = voterL1.internal_bribes(voterL1.gauges(pools[g]));
            (uint256 amount0, uint256 amount1) = handler.ghost_internalBribeBalance(internalBribe);

            uint256 internalBribeBal0 = IERC20(IPearlV2Pool(pools[g]).token0()).balanceOf(internalBribe);
            uint256 internalBribeBal1 = IERC20(IPearlV2Pool(pools[g]).token1()).balanceOf(internalBribe);

            assertEq(amount0, internalBribeBal0);
            assertEq(amount1, internalBribeBal1);
        }
    }

    function invariant_userLiquidityInGaugeIsSame() external {
        address[] memory actors = handler.actors();

        for (uint256 i; i < actors.length; ++i) {
            for (uint256 g; g < gauges.length; ++g) {
                (, uint128 liquidity,,) = GaugeV2(payable(gauges[g])).stakePos(
                    keccak256(abi.encodePacked(actors[i], handler.nftOwnerInGauge(actors[i], gauges[g])))
                );
                assertEq(liquidity, handler.ghost_userLiquidity(actors[i], gauges[g]));
            }
        }
    }

    function invariant_rewardsDistribution() external {
        assertEq(nativeOFT.balanceOf(address(this)), handler.ghost_teamEmissions());
        assertEq(nativeOFT.balanceOf(address(rewardsDistributor)), handler.ghost_rebaseRewards());

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(nativeOFT.balanceOf(gauges[i]), handler.ghost_gaugesRewards(gauges[i]));
        }
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
