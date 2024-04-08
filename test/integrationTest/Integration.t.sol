// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Bytes} from "../utils/bytes.sol";
import {Voter} from "../../src/Voter.sol";
import {GaugeV2} from "../../src/GaugeV2.sol";
import {BytesCode} from "../utils/bytesCode.sol";
import {Bribe} from "../../src/v1.5/Bribe.sol";
import {WETH9} from "../../src/mock/WETH9.sol";
import {Handler} from "./IntegrationHandler.sol";
import {Minter} from "../../src/v1.5/Minter.sol";
import {OFTMockToken} from ".././OFTMockToken.sol";
import {GaugeV2ALM} from "../../src/GaugeV2ALM.sol";
import {LiquidBox} from "../../src/box/LiquidBox.sol";
import {IPearl} from "../../src/interfaces/IPearl.sol";
import {TestERC20} from "../../src/mock/TestERC20.sol";
import {PearlToken} from "../../src/mock/PearlToken.sol";
import {GaugeV2Factory} from "../../src/GaugeV2Factory.sol";
import {BribeFactory} from "../../src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LiquidBoxFactory} from "../../src/box/LiquidBoxFactory.sol";
import {LiquidBoxManager} from "../../src/box/LiquidBoxManager.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPearlV2Pool} from "../../src/interfaces/dex/IPearlV2Pool.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {RewardsDistributor} from "../../src/v1.5/RewardsDistributor.sol";
import {LiquidityAmounts} from "../../src/libraries/LiquidityAmounts.sol";
import {IPearlV2Factory} from "../../src/interfaces/dex/IPearlV2Factory.sol";
import {EpochController} from "../../src/v1.5/automation/EpochController.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from
    "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

contract IntegrationTest is Test, Bytes {
    WETH9 public weth9;
    IPearlV2Pool public pearlV2Pool;
    IPearlV2Factory public pearlV2Factory;
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

    address[] gauges;
    address[] public pools;

    uint256 public mainChainId;
    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    address pool;

    function setUp() public {
        tERC20 = new TestERC20();
        tERC20X = new TestERC20();

        lzMainChainId = uint16(100);
        lzPoolChainId = uint16(101);

        weth9 = new WETH9();
        minter = new Minter();
        gaugeV2 = new GaugeV2();

        epochController = new EpochController();
        liquidBox = new LiquidBox();

        gaugeV2ALM = new GaugeV2ALM();
        liquidBoxFactory = new LiquidBoxFactory();

        lzEndPointMockL1 = new LZEndpointMock(lzMainChainId);
        pearlV2Pool = IPearlV2Pool(BytesCode.deployCode(pearlV2PoolBytesCode));

        bytes memory constructorArgs = abi.encode(address(this), address(pearlV2Pool));
        bytes memory deploymentData = abi.encodePacked(pearlV2FactoryBytesCode, constructorArgs);

        pearlV2Factory = IPearlV2Factory(BytesCode.deployCode(abi.encodePacked(deploymentData)));
        constructorArgs = abi.encode(address(pearlV2Factory), address(weth9), address(7));

        deploymentData = abi.encodePacked(nonfungiblePositionManagerBytesCode, constructorArgs);
        nonfungiblePositionManager = INonfungiblePositionManager(BytesCode.deployCode(deploymentData));

        nativeOFT = new OFTMockToken(address(lzEndPointMockL1));
        otherOFT = new OFTMockToken(address(lzEndPointMockL1));

        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        address voterProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 12);

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);
        votingEscrow = new VotingEscrow(address(tERC20));

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
            (address(this), address(liquidBoxFactory), address(liquidBoxFactory), address(weth9))
        );

        ERC1967Proxy liquidBoxManagerProxy = new ERC1967Proxy(address(liquidBoxManager), init);

        liquidBoxManager = LiquidBoxManager(address(liquidBoxManagerProxy));
        mainChainId = block.chainid;

        address[] memory addr = new address[](1);
        addr[0] = address(tERC20);

        bribe = new Bribe();
        bribeFactoryL1 = new BribeFactory(mainChainId);

        init = abi.encodeCall(
            BribeFactory.initialize, (address(this), address(bribe), voterProxyAddress, address(tERC20), addr)
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

        pool = pearlV2Factory.createPool(address(tERC20), address(tERC20X), 100);
        pearlV2Factory.initializePoolPrice(pool, 1 ether);

        voterL1 = new Voter(mainChainId, address(lzEndPointMockL1));

        init = abi.encodeCall(
            Voter.initialize,
            (
                address(this),
                address(this),
                address(votingEscrow),
                address(tERC20),
                address(pearlV2Factory),
                address(gaugeV2FactoryL1),
                address(bribeFactoryL1),
                address(tERC20),
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

        pearlV2Factory.setGaugeManager(address(voterL1));
        // gaugeV2 = GaugeV2(payable(voterL1.createGauge{value: 0.1 ether}(pool, "0x")));

        for (uint256 i = 0; i < 5; i++) {
            TestERC20 tokenX = new TestERC20();
            address _pool = pearlV2Factory.createPool(address(tERC20), address(tokenX), 100);
            address gauge_ = voterL1.createGauge{value: 0.1 ether}(_pool, "0x");

            gauges.push(gauge_);
            pools.push(_pool);
        }

        handler = new Handler(
            voterL1,
            address(votingEscrow),
            address(tERC20),
            pool,
            gaugeV2,
            address(epochController),
            address(lzEndPointMockL1),
            address(this),
            pools
        );

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.mintNFT.selector;
        selectors[1] = Handler.vote.selector;
        selectors[2] = Handler.distribute.selector;
        // selectors[3] = Handler.createGauge.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_bribeBalanceIsSame() external {
        for (uint256 i = 0; i < pools.length; i++) {
            Bribe b = Bribe(voterL1.external_bribes(gauges[i]));

            uint256 sum;
            address[] memory actors = handler.actors();

            for (uint256 i; i < actors.length; ++i) {
                sum += b.balanceOf(actors[i]);
            }

            console.log(handler.ghost_usersVotes(pools[i]), sum, "o");
        }
    }

    function invariant_rewardsDistribution() external {
        assertEq(tERC20.balanceOf(address(this)), handler.ghost_teamEmissions());
        assertEq(tERC20.balanceOf(address(rewardsDistributor)), handler.ghost_rebaseRewards());

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(tERC20.balanceOf(gauges[i]), handler.ghost_gaugesRewards(gauges[i]));
        }
    }

    // function test_deposit() public {
    // console.log(pool, "p");
    // (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether);

    // nonfungiblePositionManager.approve(address(gaugeV2), tokenId);

    // (address owner, uint128 liquidityAdded,,) =
    //     gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

    // assertEq(liquidityAdded, 0);
    // assertEq(gaugeV2.stakedBalance(address(this)), 0);

    // gaugeV2.deposit(tokenId);

    // (owner, liquidityAdded,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

    // assertEq(owner, address(this));
    // assertEq(liquidityToAdd, liquidityAdded);
    // assertEq(gaugeV2.stakedBalance(address(this)), 1);
    // }

    // function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd)
    //     private
    //     returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    // {
    //     deal(address(tERC20), address(this), amount1ToAdd);
    //     deal(address(tERC20X), address(this), amount0ToAdd);

    //     tERC20X.approve(address(nonfungiblePositionManager), amount0ToAdd);
    //     tERC20.approve(address(nonfungiblePositionManager), amount1ToAdd);

    //     INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
    //         token0: address(tERC20X),
    //         token1: address(tERC20),
    //         fee: 100,
    //         tickLower: -887272,
    //         tickUpper: 887272,
    //         amount0Desired: amount0ToAdd,
    //         amount1Desired: amount1ToAdd,
    //         amount0Min: 0,
    //         amount1Min: 0,
    //         recipient: address(this),
    //         deadline: block.timestamp
    //     });

    //     (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
    // }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
