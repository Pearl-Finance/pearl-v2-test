// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Voter} from "../src/Voter.sol";
import {GaugeV2} from "../src/GaugeV2.sol";
import {OFTMockToken} from "./OFTMockToken.sol";
import {GaugeV2ALM} from "../src/GaugeV2ALM.sol";
import {LiquidBox} from "../src/box/LiquidBox.sol";
import {IPearl} from "../src/interfaces/IPearl.sol";
import {GaugeV2Factory} from "../src/GaugeV2Factory.sol";
import {BribeFactory} from "../src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LiquidBoxFactory} from "../src/box/LiquidBoxFactory.sol";
import {LiquidBoxManager} from "../src/box/LiquidBoxManager.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityAmounts} from "../src/libraries/LiquidityAmounts.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IPearlV2Factory} from "../src/interfaces/dex/IPearlV2Factory.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

/**
 * @title Uint Test For GaugeV2 Contract
 * @author c-n-o-t-e
 * @dev Contract is used to test out GaugeV2 Contract-
 *      by forking the UNREAL chain to interact with....
 *
 * Functionalities Tested:
 */

contract GaugeV2Test is Test {
    using SafeERC20 for IERC20;

    Voter public voterL1;
    Voter public voterL2;

    GaugeV2 public gaugeV2;
    LiquidBox public liquidBox;

    OFTMockToken public otherOFT;
    GaugeV2ALM public gaugeV2ALM;

    OFTMockToken public nativeOFT;

    BribeFactory public bribeFactoryL1;
    BribeFactory public bribeFactoryL2;

    GaugeV2Factory public gaugeV2FactoryL1;
    GaugeV2Factory public gaugeV2FactoryL2;

    LZEndpointMock public lzEndPointMockL1;
    LZEndpointMock public lzEndPointMockL2;

    LiquidBoxFactory public liquidBoxFactory;
    LiquidBoxManager public liquidBoxManager;

    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    address pool;
    address dai = 0x665D4921fe931C0eA1390Ca4e0C422ba34d26169;

    address usdc = 0xabAa4C39cf3dF55480292BBDd471E88de8Cc3C97;
    address ustb = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;

    address pearl = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;
    address votingEscrow = 0x99E35808207986593531D3D54D898978dB4E5B04;

    address pearlFactory = 0x29b1601d3652527B8e1814347cbB1E7dBe93214E;
    address pearlPositionNFT = 0x2d59b8a48243b11B0c501991AF5602e9177ee229;

    address public daiHolder = 0x398e4966bC6a8Ea90e60665E9fB72f874F3B5207;
    address public usdcHolder = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    INonfungiblePositionManager manager =
        INonfungiblePositionManager(0x2d59b8a48243b11B0c501991AF5602e9177ee229);

    uint256 mainChainId;
    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 48203);

        gaugeV2 = new GaugeV2();
        liquidBox = new LiquidBox();

        gaugeV2ALM = new GaugeV2ALM();
        liquidBoxFactory = new LiquidBoxFactory();

        bytes memory init = abi.encodeCall(
            LiquidBoxFactory.initialize,
            (address(this), pearlFactory, address(liquidBox))
        );

        ERC1967Proxy liquidBoxFactoryProxy = new ERC1967Proxy(
            address(liquidBoxFactory),
            init
        );

        liquidBoxFactory = LiquidBoxFactory(address(liquidBoxFactoryProxy));
        liquidBoxManager = new LiquidBoxManager();

        init = abi.encodeCall(
            LiquidBoxManager.initialize,
            (address(this), address(liquidBoxFactory))
        );

        ERC1967Proxy liquidBoxManagerProxy = new ERC1967Proxy(
            address(liquidBoxManager),
            init
        );

        liquidBoxManager = LiquidBoxManager(address(liquidBoxManagerProxy));
        mainChainId = block.chainid;

        address voterProxyAddress = vm.computeCreateAddress(
            address(this),
            vm.getNonce(address(this)) + 7
        );

        address[] memory addr = new address[](1);
        addr[0] = pearl;

        bribeFactoryL1 = new BribeFactory(mainChainId);

        init = abi.encodeCall(
            BribeFactory.initialize,
            (address(this), voterProxyAddress, ustb, addr)
        );

        ERC1967Proxy bribeFactoryL1Proxy = new ERC1967Proxy(
            address(bribeFactoryL1),
            init
        );

        bribeFactoryL1 = BribeFactory(address(bribeFactoryL1Proxy));
        gaugeV2FactoryL1 = new GaugeV2Factory(mainChainId);

        init = abi.encodeCall(
            GaugeV2Factory.initialize,
            (
                address(this),
                address(gaugeV2),
                address(gaugeV2ALM),
                address(manager),
                address(liquidBoxManager)
            )
        );

        ERC1967Proxy gaugeV2FactoryL1Proxy = new ERC1967Proxy(
            address(gaugeV2FactoryL1),
            init
        );

        gaugeV2FactoryL1 = GaugeV2Factory(address(gaugeV2FactoryL1Proxy));
        pool = IPearlV2Factory(pearlFactory).getPool(dai, usdc, 1000);

        lzMainChainId = uint16(100); //unreal
        lzPoolChainId = uint16(101); //arbirum

        lzEndPointMockL1 = new LZEndpointMock(lzMainChainId);
        nativeOFT = new OFTMockToken(address(lzEndPointMockL1));

        voterL1 = new Voter(mainChainId, address(lzEndPointMockL1));

        init = abi.encodeCall(
            Voter.initialize,
            (
                address(this),
                address(this),
                votingEscrow,
                pearl,
                pearlFactory,
                address(gaugeV2FactoryL1),
                address(bribeFactoryL1),
                lzMainChainId,
                lzMainChainId
            )
        );

        ERC1967Proxy voterL1Proxy = new ERC1967Proxy(address(voterL1), init);
        voterL1 = Voter(address(voterL1Proxy));

        voterL1.setUSTB(ustb);
        voterL1.setMinter(makeAddr("minter"));

        gaugeV2 = GaugeV2(voterL1.createGauge(pool, "0x"));

        // ######################### L2 Chain ########################################

        vm.chainId(42161);

        lzEndPointMockL2 = new LZEndpointMock(lzPoolChainId);
        otherOFT = new OFTMockToken(address(lzEndPointMockL2));

        gaugeV2FactoryL2 = new GaugeV2Factory(mainChainId);

        init = abi.encodeCall(
            GaugeV2Factory.initialize,
            (
                address(this),
                address(gaugeV2),
                address(gaugeV2ALM),
                address(manager),
                address(liquidBoxManager)
            )
        );

        ERC1967Proxy gaugeV2FactoryL2Proxy = new ERC1967Proxy(
            address(gaugeV2FactoryL2),
            init
        );

        gaugeV2FactoryL2 = GaugeV2Factory(address(gaugeV2FactoryL2Proxy));
        voterL2 = new Voter(mainChainId, address(lzEndPointMockL1));

        vm.chainId(mainChainId);

        lzEndPointMockL1.setDestLzEndpoint(
            address(otherOFT),
            address(lzEndPointMockL2)
        );

        lzEndPointMockL2.setDestLzEndpoint(
            address(nativeOFT),
            address(lzEndPointMockL1)
        );

        nativeOFT.setTrustedRemoteAddress(
            lzPoolChainId,
            abi.encodePacked(address(otherOFT))
        );

        otherOFT.setTrustedRemoteAddress(
            lzMainChainId,
            abi.encodePacked(address(nativeOFT))
        );
    }

    function test_deposit() public {
        (uint256 tokenId, uint128 liquidityToAdd, , ) = mintNewPosition(
            1 ether,
            1 ether
        );

        IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);

        (address owner, uint128 liquidityAdded, , ) = gaugeV2.stakepos(
            keccak256(abi.encodePacked(address(this), tokenId))
        );

        assertEq(liquidityAdded, 0);
        assertEq(gaugeV2.stakedBalance(address(this)), 0);

        gaugeV2.deposit(tokenId);

        (owner, liquidityAdded, , ) = gaugeV2.stakepos(
            keccak256(abi.encodePacked(address(this), tokenId))
        );

        assertEq(owner, address(this));
        assertEq(liquidityToAdd, liquidityAdded);
        assertEq(gaugeV2.stakedBalance(address(this)), 1);
    }

    function test_withdraw() public {
        (uint256 tokenId, uint128 liquidityToAdd, , ) = mintNewPosition(
            1 ether,
            1 ether
        );

        IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);
        gaugeV2.deposit(tokenId);

        assertEq(gaugeV2.stakedBalance(address(this)), 1);
        gaugeV2.withdraw(tokenId, address(this), "0x");

        (, uint256 liquidityAdded, , ) = gaugeV2.stakepos(
            keccak256(abi.encodePacked(address(this), tokenId))
        );

        assertEq(0, liquidityAdded);
        assertEq(gaugeV2.stakedBalance(address(this)), 0);
    }

    event IncreaseLiquidity(
        address indexed user,
        uint256 tokenId,
        uint128 liquidity
    );

    function test_increaseLiquidity() public {
        (uint256 tokenId, uint128 liquidityToAdd, , ) = mintNewPosition(
            1 ether,
            1 ether
        );

        IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);
        gaugeV2.deposit(tokenId);

        vm.startPrank(usdcHolder);
        IERC20(usdc).transfer(address(this), 1 ether);
        vm.stopPrank();

        vm.startPrank(daiHolder);
        IERC20(dai).transfer(address(this), 1 ether);
        vm.stopPrank();

        IERC20(dai).approve(address(gaugeV2), 1 ether);
        IERC20(usdc).approve(address(gaugeV2), 1 ether);

        //Todo: assert liquidityToBeAdded is correct

        // uint256 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
        //     sqrtP(currentPrice),
        //     sqrtP60FromTick(lowerTick),
        //     sqrtP60FromTick(upperTick),
        //     params.amount0Desired,
        //     params.amount1Desired
        // );

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: 1 ether,
                    amount1Desired: 1 ether,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        vm.expectEmit(true, true, false, true);
        emit IncreaseLiquidity(
            address(this),
            tokenId,
            1998999749874 - 999499874937
        );

        (, uint128 liquidity, , ) = gaugeV2.stakepos(
            keccak256(abi.encodePacked(address(this), tokenId))
        );

        gaugeV2.increaseLiquidity(params);

        (, liquidityToAdd, , ) = gaugeV2.stakepos(
            keccak256(abi.encodePacked(address(this), tokenId))
        );

        assertEq(liquidityToAdd, liquidity + (1998999749874 - 999499874937));

        //Todo:replace 1998999749874 - 999499874937 with liquidityToBeAdded
    }

    function test_decreaseLiquidity() public {
        // (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether);
        // IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);
        // gaugeV2.deposit(tokenId);
        // vm.startPrank(usdcHolder);
        // IERC20(usdc).transfer(address(this), 1 ether);
        // vm.stopPrank();
        // vm.startPrank(daiHolder);
        // IERC20(dai).transfer(address(this), 1 ether);
        // vm.stopPrank();
        // IERC20(dai).approve(address(gaugeV2), 1 ether);
        // IERC20(usdc).approve(address(gaugeV2), 1 ether);
        //Todo: assert liquidityToBeAdded is correct
        // uint256 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
        //     sqrtP(currentPrice),
        //     sqrtP60FromTick(lowerTick),
        //     sqrtP60FromTick(upperTick),
        //     params.amount0Desired,
        //     params.amount1Desired
        // );
        // INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
        //     .IncreaseLiquidityParams({
        //     tokenId: tokenId,
        //     amount0Desired: 1 ether,
        //     amount1Desired: 1 ether,
        //     amount0Min: 0,
        //     amount1Min: 0,
        //     deadline: block.timestamp
        // });
        // vm.expectEmit(true, true, false, true);
        // emit IncreaseLiquidity(address(this), tokenId, 1998999749874 - 999499874937);
        // (, uint128 liquidity,,) = gaugeV2.stakepos(keccak256(abi.encodePacked(address(this), tokenId)));
        // gaugeV2.increaseLiquidity(params);
        // (, liquidityToAdd,,) = gaugeV2.stakepos(keccak256(abi.encodePacked(address(this), tokenId)));
        // assertEq(liquidityToAdd, liquidity + (1998999749874 - 999499874937));
        //Todo:replace 1998999749874 - 999499874937 with liquidityToBeAdded
    }

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;

    function mintNewPosition(
        uint256 amount0ToAdd,
        uint256 amount1ToAdd
    )
        internal
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        vm.startPrank(usdcHolder);
        IERC20(usdc).transfer(address(this), amount1ToAdd);
        vm.stopPrank();

        vm.startPrank(daiHolder);
        IERC20(dai).transfer(address(this), amount1ToAdd);
        vm.stopPrank();

        IERC20(dai).approve(address(manager), amount0ToAdd);
        IERC20(usdc).approve(address(manager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: dai,
                token1: usdc,
                fee: 1000,
                // By using TickMath.MIN_TICK and TickMath.MAX_TICK,
                // we are providing liquidity across the whole range of the pool.
                // Not recommended in production.
                //Todo: Update ticks to be within current ticks.
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = manager.mint(params);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
