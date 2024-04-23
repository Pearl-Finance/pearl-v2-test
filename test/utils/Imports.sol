// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Bytes} from "./bytes.sol";
import {Voter} from "src/Voter.sol";
import {GaugeV2} from "src/GaugeV2.sol";
import {Bribe} from "src/v1.5/Bribe.sol";
import {WETH9} from "src/mock/WETH9.sol";
import {BytesCode} from "./bytesCode.sol";
import {Minter} from "src/v1.5/Minter.sol";
import {GaugeV2ALM} from "src/GaugeV2ALM.sol";
import {LiquidBox} from "src/box/LiquidBox.sol";
import {PearlV2Pool} from "xed/PearlV2Pool.sol";
import {IPearl} from "src/interfaces/IPearl.sol";
import {TestERC20} from "src/mock/TestERC20.sol";
import {OFTMockToken} from "./OFTMockToken.sol";
import {PearlToken} from "src/mock/PearlToken.sol";
import {PearlV2Factory} from "xed/PearlV2Factory.sol";
import {GaugeV2Factory} from "src/GaugeV2Factory.sol";
import {BribeFactory} from "src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LiquidBoxFactory} from "src/box/LiquidBoxFactory.sol";
import {LiquidBoxManager} from "src/box/LiquidBoxManager.sol";
import {ISwapRouter} from "src/interfaces/dex/ISwapRouter.sol";
import {IPearlV2Pool} from "src/interfaces/dex/IPearlV2Pool.sol";
import {RewardsDistributor} from "src/v1.5/RewardsDistributor.sol";
import {LiquidityAmounts} from "src/libraries/LiquidityAmounts.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPearlV2Factory} from "src/interfaces/dex/IPearlV2Factory.sol";
import {EpochController} from "src/v1.5/automation/EpochController.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from
    "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

contract Imports is Test, Bytes {
    WETH9 public weth;
    TestERC20 tERC20X;

    Bribe public bribe;
    Voter public voterL1;

    Voter public voterL2;
    Minter public minter;

    GaugeV2 public gaugeV2;

    TestERC20 public tERC20;
    GaugeV2 public gaugeV2L2;

    VotingEscrow votingEscrow;
    LiquidBox public liquidBox;

    VotingEscrowVesting vesting;
    LiquidBox public liquidBoxL2;

    GaugeV2ALM public gaugeV2ALM;
    OFTMockToken public otherOFT;

    OFTMockToken public nativeOFT;
    GaugeV2ALM public gaugeV2ALML2;

    PearlV2Pool public pearlV2Pool;
    BribeFactory public bribeFactory;

    BribeFactory public bribeFactoryL2;
    PearlV2Factory public pearlV2Factory;

    EpochController public epochController;
    GaugeV2Factory public gaugeV2FactoryL1;

    GaugeV2Factory public gaugeV2FactoryL2;
    LZEndpointMock public lzEndPointMockL1;

    LZEndpointMock public lzEndPointMockL2;
    LiquidBoxFactory public liquidBoxFactory;

    LiquidBoxManager public liquidBoxManager;
    LiquidBoxFactory public liquidBoxFactoryL2;

    LiquidBoxManager public liquidBoxManagerL2;
    RewardsDistributor public rewardsDistributor;
    INonfungiblePositionManager public nonfungiblePositionManager;

    address[] box;
    address[] gauges;
    address[] public pools;

    IPearlV2Pool pool;
    address router;

    uint256 public mainChainId;
    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    function l1SetUp() public {
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
        bribeFactory = new BribeFactory(mainChainId);

        init = abi.encodeCall(
            BribeFactory.initialize, (address(this), address(bribe), voterProxyAddress, address(nativeOFT), addr)
        );

        ERC1967Proxy bribeFactoryProxy = new ERC1967Proxy(address(bribeFactory), init);

        bribeFactory = BribeFactory(address(bribeFactoryProxy));
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
                address(bribeFactory),
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
    }

    // function l2SetUp() public {
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
    //         abi.encodeCall(LiquidBoxFactory.initialize, (address(this), pearlFactory, address(liquidBoxL2)));

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
    //             address(manager),
    //             address(liquidBoxManagerL2),
    //             address(voterL2)
    //         )
    //     );

    //     ERC1967Proxy gaugeV2FactoryL2Proxy = new ERC1967Proxy(address(gaugeV2FactoryL2), init);

    //     gaugeV2FactoryL2 = GaugeV2Factory(address(gaugeV2FactoryL2Proxy));

    //     address voterProxyAddressL2 = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);

    //     bribeFactoryL2 = new BribeFactory(mainChainId);

    //     init = abi.encodeCall(BribeFactory.initialize, (address(this), address(bribe), voterProxyAddressL2, ustb, addr));
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
    //             pearlFactory,
    //             address(gaugeV2FactoryL2),
    //             address(bribeFactoryL2),
    //             ustb,
    //             lzMainChainId,
    //             lzPoolChainId
    //         )
    //     );

    //     ERC1967Proxy voterL2Proxy = new ERC1967Proxy(address(voterL2), init);
    //     voterL2 = Voter(address(voterL2Proxy));

    //     // vm.startPrank(0x95e3664633A8650CaCD2c80A0F04fb56F65DF300);
    //     // IPearlV2Factory(pearlFactory).setGaugeManager(address(voterL2));
    //     // vm.stopPrank();

    //     // lzEndPointMockL1.setDestLzEndpoint(
    //     //     address(voterL2),
    //     //     address(lzEndPointMockL2)
    //     // );
    //     // lzEndPointMockL2.setDestLzEndpoint(
    //     //     address(voterL1),
    //     //     address(lzEndPointMockL1)
    //     // );

    //     // lzEndPointMockL1.setDestLzEndpoint(
    //     //     address(otherOFT),
    //     //     address(lzEndPointMockL2)
    //     // );
    //     // lzEndPointMockL2.setDestLzEndpoint(
    //     //     address(nativeOFT),
    //     //     address(lzEndPointMockL1)
    //     // );

    //     // nativeOFT.setTrustedRemoteAddress(
    //     //     lzPoolChainId,
    //     //     abi.encodePacked(address(otherOFT))
    //     // );
    //     // otherOFT.setTrustedRemoteAddress(
    //     //     lzMainChainId,
    //     //     abi.encodePacked(address(nativeOFT))
    //     // );

    //     // voterL1.setTrustedRemote(
    //     //     lzPoolChainId,
    //     //     abi.encodePacked(address(voterL2), address(voterL1))
    //     // );
    //     // voterL2.setTrustedRemote(
    //     //     lzMainChainId,
    //     //     abi.encodePacked(address(voterL1), address(voterL2))
    //     // );

    //     // poolL2 = 0x3dDc6EbfB3BB43aDAED7Ef1Aaae75fAD8caa3419;

    //     // assertEq(voterL1.getLzPoolsLength(), 0);
    //     // gaugeV2L2 = GaugeV2(
    //     //     payable(voterL2.createGauge{value: 10 ether}(poolL2, ""))
    //     // );

    //     // assertEq(voterL1.getLzPoolsLength(), 1);
    // }

    function testExcluded() public {}
}
