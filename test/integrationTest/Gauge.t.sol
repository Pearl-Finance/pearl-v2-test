// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Bytes} from "../utils/bytes.sol";
import {Voter} from "../../src/Voter.sol";
import {Handler} from "./GaugeHandler.sol";
import {GaugeV2} from "../../src/GaugeV2.sol";
import {Bribe} from "../../src/v1.5/Bribe.sol";
import {WETH9} from "../../src/mock/WETH9.sol";
import {PearlV2Pool} from "xed/PearlV2Pool.sol";
import {BytesCode} from "../utils/bytesCode.sol";
import {Minter} from "../../src/v1.5/Minter.sol";
import {OFTMockToken} from ".././OFTMockToken.sol";
import {GaugeV2ALM} from "../../src/GaugeV2ALM.sol";
import {PearlV2Factory} from "xed/PearlV2Factory.sol";
import {PearlV2Factory} from "xed/PearlV2Factory.sol";
import {LiquidBox} from "../../src/box/LiquidBox.sol";
import {IPearl} from "../../src/interfaces/IPearl.sol";
import {TestERC20} from "../../src/mock/TestERC20.sol";
import {PearlToken} from "../../src/mock/PearlToken.sol";
import "@uniswap/v3-core/contracts/libraries/Position.sol";
import {GaugeV2Factory} from "../../src/GaugeV2Factory.sol";
import {BribeFactory} from "../../src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LiquidBoxFactory} from "../../src/box/LiquidBoxFactory.sol";
import {LiquidBoxManager} from "../../src/box/LiquidBoxManager.sol";
import {ISwapRouter} from "../../src/interfaces/dex/ISwapRouter.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPearlV2Pool} from "../../src/interfaces/dex/IPearlV2Pool.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {RewardsDistributor} from "../../src/v1.5/RewardsDistributor.sol";
import {LiquidityAmounts} from "../../src/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {IPearlV2Factory} from "../../src/interfaces/dex/IPearlV2Factory.sol";
import {EpochController} from "../../src/v1.5/automation/EpochController.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from
    "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

contract GaugeInvariantTest is Test, Bytes {
    WETH9 public weth;
    PearlV2Pool public pearlV2Pool;
    PearlV2Factory public pearlV2Factory;
    INonfungiblePositionManager public nonfungiblePositionManager;

    Voter public voterL1;
    Voter public voterL2;

    Bribe public bribe;

    GaugeV2 public gaugeV2;
    GaugeV2 public gaugeV2L2;

    LiquidBox public liquidBox;
    LiquidBox public liquidBoxL2;

    GaugeV2ALM public gaugeV2ALM;
    GaugeV2ALM public gaugeV2ALML2;

    OFTMockToken public otherOFT;
    OFTMockToken public nativeOFT;

    Minter public minter;
    VotingEscrow votingEscrow;
    VotingEscrowVesting vesting;

    EpochController public epochController;
    RewardsDistributor public rewardsDistributor;

    BribeFactory public bribeFactoryL1;
    BribeFactory public bribeFactoryL2;

    GaugeV2Factory public gaugeV2FactoryL1;
    GaugeV2Factory public gaugeV2FactoryL2;

    LZEndpointMock public lzEndPointMockL1;
    LZEndpointMock public lzEndPointMockL2;

    LiquidBoxFactory public liquidBoxFactory;
    LiquidBoxManager public liquidBoxManager;

    LiquidBoxFactory public liquidBoxFactoryL2;
    LiquidBoxManager public liquidBoxManagerL2;

    TestERC20 public tERC20;
    TestERC20 tERC20X;
    Handler public handler;

    address[] box;
    address[] gauges;
    address[] public pools;

    address router;

    uint256 public mainChainId;
    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    uint256 internal constant ONE = 1;
    mapping(bytes32 => Position.Info) public positions;

    address pool;

    function setUp() public {
        tERC20 = new TestERC20();
        tERC20X = new TestERC20();

        lzMainChainId = uint16(100);
        lzPoolChainId = uint16(101);

        weth = new WETH9();
        minter = new Minter();
        gaugeV2 = new GaugeV2();

        epochController = new EpochController();
        liquidBox = new LiquidBox();

        gaugeV2ALM = new GaugeV2ALM();
        liquidBoxFactory = new LiquidBoxFactory();

        lzEndPointMockL1 = new LZEndpointMock(lzMainChainId);
        pearlV2Pool = new PearlV2Pool();
        pearlV2Factory = new PearlV2Factory(address(this), address(pearlV2Pool));

        bytes memory constructorArgs = abi.encode(address(pearlV2Factory), address(weth), address(7));
        bytes memory deploymentData = abi.encodePacked(nonfungiblePositionManagerBytesCode, constructorArgs);
        nonfungiblePositionManager = INonfungiblePositionManager(BytesCode.deployCode(deploymentData));

        constructorArgs = abi.encode(address(pearlV2Factory), address(weth));
        deploymentData = abi.encodePacked(swapRouter, constructorArgs);
        router = BytesCode.deployCode(deploymentData);

        nativeOFT = new OFTMockToken(address(lzEndPointMockL1));
        otherOFT = new OFTMockToken(address(lzEndPointMockL1));

        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        address voterProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 12);

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);
        votingEscrow = new VotingEscrow(address(nativeOFT));

        bytes memory init =
            abi.encodeCall(VotingEscrow.initialize, (address(vesting), address(voterProxyAddress), address(0)));

        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrow), init);
        votingEscrow = VotingEscrow(address(votingEscrowProxy));

        init = abi.encodeCall(LiquidBoxFactory.initialize, (address(this), address(pearlV2Factory), address(liquidBox)));

        ERC1967Proxy liquidBoxFactoryProxy = new ERC1967Proxy(address(liquidBoxFactory), init);

        liquidBoxFactory = LiquidBoxFactory(address(liquidBoxFactoryProxy));
        liquidBoxManager = new LiquidBoxManager();

        init = abi.encodeCall(
            LiquidBoxManager.initialize,
            (address(this), address(liquidBoxFactory), address(liquidBoxFactory), address(weth))
        );

        ERC1967Proxy liquidBoxManagerProxy = new ERC1967Proxy(address(liquidBoxManager), init);

        liquidBoxManager = LiquidBoxManager(address(liquidBoxManagerProxy));
        liquidBoxManager.setManager(address(11));
        mainChainId = block.chainid;

        address[] memory addr = new address[](1);
        addr[0] = address(nativeOFT);

        bribe = new Bribe();
        bribeFactoryL1 = new BribeFactory(mainChainId);

        init = abi.encodeCall(
            BribeFactory.initialize, (address(this), address(bribe), voterProxyAddress, address(nativeOFT), addr)
        );

        ERC1967Proxy bribeFactoryL1Proxy = new ERC1967Proxy(address(bribeFactoryL1), init);

        bribeFactoryL1 = BribeFactory(address(bribeFactoryL1Proxy));
        gaugeV2FactoryL1 = new GaugeV2Factory(mainChainId);

        init = abi.encodeCall(
            GaugeV2Factory.initialize,
            (
                address(this),
                address(gaugeV2),
                address(gaugeV2ALM),
                address(nonfungiblePositionManager),
                address(liquidBoxManager),
                address(voterProxyAddress)
            )
        );

        ERC1967Proxy gaugeV2FactoryL1Proxy = new ERC1967Proxy(address(gaugeV2FactoryL1), init);

        gaugeV2FactoryL1 = GaugeV2Factory(address(gaugeV2FactoryL1Proxy));

        voterL1 = new Voter(mainChainId, address(lzEndPointMockL1));

        init = abi.encodeCall(
            Voter.initialize,
            (
                address(this),
                address(this),
                address(votingEscrow),
                address(nativeOFT),
                address(pearlV2Factory),
                address(gaugeV2FactoryL1),
                address(bribeFactoryL1),
                address(nativeOFT),
                lzMainChainId,
                lzMainChainId
            )
        );

        ERC1967Proxy voterL1Proxy = new ERC1967Proxy(address(voterL1), init);
        voterL1 = Voter(address(voterL1Proxy));

        rewardsDistributor = new RewardsDistributor();
        init = abi.encodeCall(RewardsDistributor.initialize, (address(this), address(votingEscrow)));

        ERC1967Proxy rewardsDistributorProxy = new ERC1967Proxy(address(rewardsDistributor), init);
        rewardsDistributor = RewardsDistributor(address(rewardsDistributorProxy));

        init = abi.encodeCall(
            Minter.initialize, (address(this), address(voterL1), address(votingEscrow), address(rewardsDistributor))
        );

        ERC1967Proxy minterProxy = new ERC1967Proxy(address(minter), init);
        minter = Minter(address(minterProxy));
        rewardsDistributor.setDepositor(address(minter));

        init = abi.encodeCall(EpochController.initialize, (address(this), address(minter), address(voterL1)));
        ERC1967Proxy epochControllerProxy = new ERC1967Proxy(address(epochController), init);
        epochController = EpochController(address(epochControllerProxy));

        voterL1.setMinter(address(minter));
        voterL1.setEpochController(address(epochController));

        pearlV2Factory.grantRole(keccak256("GAUGE_MANAGER"), address(voterL1));
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

    // function invariant_claimedFeeToInternalBribeIsSame() external {
    //     for (uint256 g; g < gauges.length; ++g) {
    //         address internalBribe = voterL1.internal_bribes(voterL1.gauges(pools[g]));
    //         (uint256 amount0, uint256 amount1) = handler.ghost_internalBribeBalance(internalBribe);

    //         uint256 internalBribeBal0 = IERC20(IPearlV2Pool(pools[g]).token0()).balanceOf(internalBribe);
    //         uint256 internalBribeBal1 = IERC20(IPearlV2Pool(pools[g]).token1()).balanceOf(internalBribe);

    //         console.log(amount0, internalBribeBal0);
    //         console.log(amount1, internalBribeBal1);

    //         assertEq(amount0, internalBribeBal0);
    //         assertEq(amount1, internalBribeBal1);
    //     }
    // }

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
