// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./utils/Imports.sol";

/**
 * @title Uint Test For GaugeV2 Contract
 * @author c-n-o-t-e
 * @dev Contract is used to test out GaugeV2 Contract-
 *      by forking the UNREAL chain to interact with....
 *
 * Functionalities Tested:
 */

contract GaugeV2Test is Imports {
    int24 tickLower = 6931;
    int24 tickUpper = 27081;

    function setUp() public {
        l1SetUp();
        TestERC20 tokenX = new TestERC20();

        pool = IPearlV2Pool(pearlV2Factory.createPool(address(nativeOFT), address(tokenX), 100));
        pearlV2Factory.initializePoolPrice(address(pool), TickMath.getSqrtRatioAtTick(23027));
        gaugeV2 = GaugeV2(payable(voterL1.createGauge{value: 0.1 ether}(address(pool), "0x")));
    }

    function test_deposit() public {
        (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, address(pool), address(this));

        IERC721(address(nonfungiblePositionManager)).approve(address(gaugeV2), tokenId);

        (address owner, uint128 liquidityAdded,,) =
            gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        assertEq(liquidityAdded, 0);
        assertEq(gaugeV2.stakedBalance(address(this)), 0);

        gaugeV2.deposit(tokenId);
        (owner, liquidityAdded,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        assertEq(owner, address(this));
        assertEq(liquidityToAdd, liquidityAdded);
        assertEq(gaugeV2.stakedBalance(address(this)), 1);
    }

    function test_claim_reward() public {
        vote((address(pool)));
        (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, address(pool), address(this));

        vm.warp(block.timestamp + minter.nextPeriod());
        epochController.distribute();

        IERC721(address(nonfungiblePositionManager)).approve(address(gaugeV2), tokenId);

        gaugeV2.deposit(tokenId);
        console.log(nativeOFT.balanceOf(address(this)), "before");

        vm.warp(block.timestamp + 1 hours);

        gaugeV2.collectReward(tokenId);
        console.log(nativeOFT.balanceOf(address(this)), "after");
    }

    function test_distribution() public {
        vote(address(pool));

        console.log(nativeOFT.balanceOf(address(this)), "before");

        vm.warp(block.timestamp + minter.nextPeriod());
        epochController.distribute();
        console.log(nativeOFT.balanceOf(address(this)), "after");
    }

    function test_withdraw() public {
        (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, address(pool), address(this));

        IERC721(address(nonfungiblePositionManager)).approve(address(gaugeV2), tokenId);
        gaugeV2.deposit(tokenId);

        assertEq(gaugeV2.stakedBalance(address(this)), 1);
        gaugeV2.withdraw(tokenId, address(this), "0x");

        (, uint256 liquidityAdded,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        assertEq(0, liquidityAdded);
        assertEq(gaugeV2.stakedBalance(address(this)), 0);
    }

    function test_increaseLiquidity() public {
        (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, address(pool), address(this));
        IERC721(address(nonfungiblePositionManager)).approve(address(gaugeV2), tokenId);

        gaugeV2.deposit(tokenId);

        address token0 = IPearlV2Pool(pool).token0();
        address token1 = IPearlV2Pool(pool).token1();

        deal(address(token0), address(this), 1 ether);
        deal(address(token1), address(this), 1 ether);

        IERC20(token0).approve(address(gaugeV2), 1 ether);
        IERC20(token1).approve(address(gaugeV2), 1 ether);

        //Todo: assert liquidityToBeAdded is correct

        // uint256 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
        //     sqrtP(currentPrice),
        //     sqrtP60FromTick(lowerTick),
        //     sqrtP60FromTick(upperTick),
        //     params.amount0Desired,
        //     params.amount1Desired
        // );

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (, uint128 liquidity,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        gaugeV2.increaseLiquidity(params);

        (, liquidityToAdd,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        // assertEq(liquidityToAdd, liquidity + (1998999749874 - 999499874937));

        //Todo:replace 1998999749874 - 999499874937 with liquidityToBeAdded
    }

    function test_decreaseLiquidity() public {
        (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether, address(pool), address(this));
        IERC721(address(nonfungiblePositionManager)).approve(address(gaugeV2), tokenId);
        gaugeV2.deposit(tokenId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidityToAdd,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        (address owner, uint128 liquidityAdded,,) =
            gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        assertEq(liquidityToAdd, liquidityAdded);
        assertEq(gaugeV2.stakedBalance(address(this)), 1);

        gaugeV2.decreaseLiquidity(params);

        (owner, liquidityAdded,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

        assertEq(liquidityAdded, 0);
    }

    function vote(address _pool) private {
        nativeOFT.mint(address(this), 2 ether);
        nativeOFT.approve(address(votingEscrow), 2 ether);

        (bool success0,) = address(votingEscrow).call(
            abi.encodeWithSignature("mint(address,uint256,uint256)", address(this), 1 ether, 3 weeks)
        );
        assert(success0);

        address[] memory addr = new address[](1);
        addr[0] = _pool;

        uint256[] memory amt = new uint256[](1);
        amt[0] = 1;

        voterL1.vote(addr, amt);
    }

    function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd, address _pool, address user)
        public
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address token0 = IPearlV2Pool(_pool).token0();
        address token1 = IPearlV2Pool(_pool).token1();

        deal(address(token0), user, amount0ToAdd);
        deal(address(token1), user, amount1ToAdd);

        IERC20(token0).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(token1).approve(address(nonfungiblePositionManager), amount1ToAdd);

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

    // function test_shouldUpdatePendingReward() external {
    //     vote(poolL2);
    //     gaugeV2L2 = GaugeV2(payable(voterL1.gauges(poolL2)));

    //     assertEq(gaugeV2L2.pendingReward(), 0);
    //     vm.warp(block.timestamp + minter.nextPeriod());
    //     assertEq(nativeOFT.balanceOf(address(gaugeV2L2)), 0);

    //     epochController.distribute();
    //     assertGt(gaugeV2L2.pendingReward(), 0);
    //     assertGt(nativeOFT.balanceOf(address(gaugeV2L2)), 0);
    // }

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

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
