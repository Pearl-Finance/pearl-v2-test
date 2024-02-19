// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OFTMockToken} from "./OFTMockToken.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GaugeV2} from "../src/GaugeV2.sol";
import {GaugeV2ALM} from "../src/GaugeV2ALM.sol";
import {GaugeV2Factory} from "../src/GaugeV2Factory.sol";
import {LiquidBox} from "../src/box/LiquidBox.sol";
import {LiquidBoxFactory} from "../src/box/LiquidBoxFactory.sol";
import {LiquidBoxManager} from "../src/box/LiquidBoxManager.sol";
import {IPearlV2Factory} from "../src/interfaces/dex/IPearlV2Factory.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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

    OFTMockToken public nativeOFT;
    OFTMockToken public otherOFT;

    GaugeV2 public gaugeV2;
    LiquidBox public liquidBox;

    GaugeV2ALM public gaugeV2ALM;
    GaugeV2Factory public gaugeV2FactoryL1;
    GaugeV2Factory public gaugeV2FactoryL2;

    LiquidBoxFactory public liquidBoxFactory;
    LiquidBoxManager public liquidBoxManager;

    address pearlHolder = 0x95e3664633A8650CaCD2c80A0F04fb56F65DF300;
    address VotingEscrowVesting = 0xA1Bc24d9043C364bF9BAc192ef9a46B8d8f24dCD;

    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    address votingEscrow = 0xee60171b3A81EE2DF0caf0aAd894772B6Acaa772;
    address pearlFactory = 0x29b1601d3652527B8e1814347cbB1E7dBe93214E;
    address pool;
    address nonfungiblePositionManager =
        0x2d59b8a48243b11B0c501991AF5602e9177ee229;
    address rewardToken;
    address distribution;
    address internalBribe;
    bool isForPair;

    address pearl = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;
    address ustb = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;

    LZEndpointMock public lzEndPointMockL1;
    LZEndpointMock public lzEndPointMockL2;

    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;
    uint256 mainChainId;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 11000);
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
        gaugeV2FactoryL1 = new GaugeV2Factory(mainChainId);

        init = abi.encodeCall(
            GaugeV2Factory.initialize,
            (
                address(this),
                address(gaugeV2),
                address(gaugeV2ALM),
                nonfungiblePositionManager,
                address(liquidBoxManager)
            )
        );

        ERC1967Proxy gaugeV2FactoryL1Proxy = new ERC1967Proxy(
            address(gaugeV2FactoryL1),
            init
        );
        gaugeV2FactoryL1 = GaugeV2Factory(address(gaugeV2FactoryL1Proxy));

        pool = IPearlV2Factory(pearlFactory).createPool(
            address(pearl),
            address(ustb),
            3000
        );

        lzMainChainId = uint16(100); //unreal
        lzPoolChainId = uint16(101); //arbirum

        lzEndPointMockL1 = new LZEndpointMock(lzMainChainId);
        nativeOFT = new OFTMockToken(address(lzEndPointMockL1));

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
                nonfungiblePositionManager,
                address(liquidBoxManager)
            )
        );

        ERC1967Proxy gaugeV2FactoryL2Proxy = new ERC1967Proxy(
            address(gaugeV2FactoryL2),
            init
        );
        gaugeV2FactoryL2 = GaugeV2Factory(address(gaugeV2FactoryL2Proxy));

        vm.chainId(mainChainId);

        //------  setTrustedRemote(s) -------------------------------------------------------

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

    function test_initialize() public {
        assertEq(gaugeV2FactoryL1.almManager(), address(liquidBoxManager));
        assertEq(gaugeV2FactoryL1.gaugeCLImplementation(), address(gaugeV2));
        assertEq(
            gaugeV2FactoryL1.gaugeALMImplementation(),
            address(gaugeV2ALM)
        );

        assertEq(
            gaugeV2FactoryL1.nonfungiblePositionManager(),
            nonfungiblePositionManager
        );
    }
}
