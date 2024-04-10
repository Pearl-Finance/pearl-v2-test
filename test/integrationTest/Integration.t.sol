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
import {PearlV2Factory} from "xed/PearlV2Factory.sol";
import {PearlV2Pool} from "xed/PearlV2Pool.sol";
import {EpochController} from "../../src/v1.5/automation/EpochController.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from
    "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

contract IntegrationTest is Test, Bytes {
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

        pool = pearlV2Factory.createPool(address(tERC20), address(tERC20X), 100);
        pearlV2Factory.initializePoolPrice(pool, 1 ether);

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
        uint256 numberOfAssets = bound(type(uint8).max, 0, 100);

        for (uint256 i = 0; i < 1; i++) {
            TestERC20 tokenX = new TestERC20();
            address _pool = pearlV2Factory.createPool(address(nativeOFT), address(tokenX), 100);

            pearlV2Factory.initializePoolPrice(_pool, 1 ether);
            address gauge_ = voterL1.createGauge{value: 0.1 ether}(_pool, "0x");

            gauges.push(gauge_);
            pools.push(_pool);
        }

        handler = new Handler(
            voterL1,
            address(votingEscrow),
            address(nativeOFT),
            gaugeV2,
            address(epochController),
            address(lzEndPointMockL1),
            address(nonfungiblePositionManager),
            pools
        );

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.mintNFT.selector;
        selectors[2] = Handler.vote.selector;
        selectors[3] = Handler.distribute.selector;
        selectors[4] = Handler.increaseLiquidity.selector;
        selectors[5] = Handler.decreaseLiquidity.selector;
        selectors[6] = Handler.withdraw.selector;
        // selectors[3] = Handler.claimDistributionRewards.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));

        // l2();
        // vm.chainId(mainChainId);
    }

    function invariant_veNftCountIsSame() external {
        assertEq(votingEscrow.totalSupply(), handler.ghost_veNftCount());
    }

    // function invariant_userLiquidityInGaugeIsSame() external {}

    function invariant_rewardsDistribution() external {
        assertEq(nativeOFT.balanceOf(address(this)), handler.ghost_teamEmissions());
        assertEq(nativeOFT.balanceOf(address(rewardsDistributor)), handler.ghost_rebaseRewards());

        for (uint256 i = 0; i < pools.length; i++) {
            assertEq(nativeOFT.balanceOf(gauges[i]), handler.ghost_gaugesRewards(gauges[i]));
        }
    }

    // function test_deposit() public {
    //     (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether);
    //     console.log(tokenId, "lol");
    //     // bytes memory b = BytesCode.getContractCreationCode(address(pearlV2Pool));

    //     // console.logBytes32(keccak256(b));

    //     // nonfungiblePositionManager.approve(address(gaugeV2), tokenId);

    //     // (address owner, uint128 liquidityAdded,,) =
    //     //     gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

    //     // assertEq(liquidityAdded, 0);
    //     // assertEq(gaugeV2.stakedBalance(address(this)), 0);

    //     // gaugeV2.deposit(tokenId);

    //     // (owner, liquidityAdded,,) = gaugeV2.stakePos(keccak256(abi.encodePacked(address(this), tokenId)));

    //     // assertEq(owner, address(this));
    //     // assertEq(liquidityToAdd, liquidityAdded);
    //     // assertEq(gaugeV2.stakedBalance(address(this)), 1);
    // }

    // function l2() public {
    //     vm.chainId(42161);

    //     lzEndPointMockL2 = new LZEndpointMock(lzPoolChainId);
    //     otherOFT = new OFTMockToken(address(lzEndPointMockL2));

    //     address[] memory addr = new address[](1);
    //     addr[0] = address(otherOFT);

    //     gaugeV2L2 = new GaugeV2();
    //     liquidBoxL2 = new LiquidBox();
    //     gaugeV2ALML2 = new GaugeV2ALM();

    //     liquidBoxFactoryL2 = new LiquidBoxFactory();

    //     bytes memory init =
    //         abi.encodeCall(LiquidBoxFactory.initialize, (address(this), address(pearlV2Factory), address(liquidBoxL2)));

    //     ERC1967Proxy liquidBoxFactoryProxy = new ERC1967Proxy(address(liquidBoxFactoryL2), init);
    //     liquidBoxFactoryL2 = LiquidBoxFactory(address(liquidBoxFactoryProxy));

    //     liquidBoxManagerL2 = new LiquidBoxManager();
    //     init = abi.encodeCall(
    //         LiquidBoxManager.initialize, (address(this), address(liquidBoxFactoryL2), address(6), address(6))
    //     );

    //     ERC1967Proxy liquidBoxManagerProxy = new ERC1967Proxy(address(liquidBoxManagerL2), init);
    //     liquidBoxManagerL2 = LiquidBoxManager(address(liquidBoxManagerProxy));

    //     gaugeV2FactoryL2 = new GaugeV2Factory(mainChainId);

    //     init = abi.encodeCall(
    //         GaugeV2Factory.initialize,
    //         (
    //             address(this),
    //             address(gaugeV2L2),
    //             address(gaugeV2ALML2),
    //             address(nonfungiblePositionManager),
    //             address(liquidBoxManagerL2),
    //             address(voterL2)
    //         )
    //     );

    //     ERC1967Proxy gaugeV2FactoryL2Proxy = new ERC1967Proxy(address(gaugeV2FactoryL2), init);

    //     gaugeV2FactoryL2 = GaugeV2Factory(address(gaugeV2FactoryL2Proxy));

    //     address voterProxyAddressL2 = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);

    //     bribeFactoryL2 = new BribeFactory(mainChainId);

    //     init = abi.encodeCall(
    //         BribeFactory.initialize, (address(this), address(bribe), voterProxyAddressL2, address(otherOFT), addr)
    //     );
    //     ERC1967Proxy bribeFactoryL2Proxy = new ERC1967Proxy(address(bribeFactoryL2), init);

    //     bribeFactoryL2 = BribeFactory(address(bribeFactoryL2Proxy));
    //     voterL2 = new Voter(mainChainId, address(lzEndPointMockL2));

    //     init = abi.encodeCall(
    //         Voter.initialize,
    //         (
    //             address(this),
    //             address(this),
    //             address(0),
    //             address(otherOFT),
    //             address(pearlV2Factory),
    //             address(gaugeV2FactoryL2),
    //             address(bribeFactoryL2),
    //             address(otherOFT),
    //             lzMainChainId,
    //             lzPoolChainId
    //         )
    //     );

    //     ERC1967Proxy voterL2Proxy = new ERC1967Proxy(address(voterL2), init);
    //     voterL2 = Voter(address(voterL2Proxy));

    //     pearlV2Factory.setGaugeManager(address(voterL2));

    //     lzEndPointMockL1.setDestLzEndpoint(address(voterL2), address(lzEndPointMockL2));
    //     lzEndPointMockL2.setDestLzEndpoint(address(voterL1), address(lzEndPointMockL1));

    //     lzEndPointMockL1.setDestLzEndpoint(address(otherOFT), address(lzEndPointMockL2));
    //     lzEndPointMockL2.setDestLzEndpoint(address(nativeOFT), address(lzEndPointMockL1));

    //     nativeOFT.setTrustedRemoteAddress(lzPoolChainId, abi.encodePacked(address(otherOFT)));
    //     otherOFT.setTrustedRemoteAddress(lzMainChainId, abi.encodePacked(address(nativeOFT)));

    //     voterL1.setTrustedRemote(lzPoolChainId, abi.encodePacked(address(voterL2), address(voterL1)));
    //     voterL2.setTrustedRemote(lzMainChainId, abi.encodePacked(address(voterL1), address(voterL2)));

    //     // gaugeV2L2 = GaugeV2(payable(voterL2.createGauge{value: 10 ether}(poolL2, "")));

    //     // assertEq(voterL1.getLzPoolsLength(), 1);
    // }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
