// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Voter} from "../src/Voter.sol";
import {GaugeV2} from "../src/GaugeV2.sol";
import {Bribe} from "../src/v1.5/Bribe.sol";
import {Minter} from "../src/v1.5/Minter.sol";
import {OFTMockToken} from "./utils/OFTMockToken.sol";
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
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {IPearlV2Factory} from "../src/interfaces/dex/IPearlV2Factory.sol";
import {EpochController} from "../src/v1.5/automation/EpochController.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from
    "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

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

    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    address pool;
    address dai = 0x665D4921fe931C0eA1390Ca4e0C422ba34d26169;

    address usdc = 0xabAa4C39cf3dF55480292BBDd471E88de8Cc3C97;
    address ustb = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;

    address pearlFactory = 0x29b1601d3652527B8e1814347cbB1E7dBe93214E;
    address pearlPositionNFT = 0x2d59b8a48243b11B0c501991AF5602e9177ee229;

    address public daiHolder = 0x398e4966bC6a8Ea90e60665E9fB72f874F3B5207;
    address public usdcHolder = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    INonfungiblePositionManager manager = INonfungiblePositionManager(0x2d59b8a48243b11B0c501991AF5602e9177ee229);

    address poolL2;
    address daiL2 = 0xB0bc765A7a8dC333Ce9C27175eeD203B8fBd92f0;
    address usdcL2 = 0x8FBc64e70a32Ad8F3c3669a977FA58BACfa01609;

    address public daiHolderL2 = 0x398e4966bC6a8Ea90e60665E9fB72f874F3B5207;
    address public usdcHolderL2 = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    uint256 mainChainId;
    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    uint256 unrealFork = vm.createFork(UNREAL_RPC_URL);

    function setUp() public {
        vm.selectFork(unrealFork);
        // vm.createSelectFork(UNREAL_RPC_URL, 18337);

        minter = new Minter();
        gaugeV2 = new GaugeV2();

        epochController = new EpochController();
        liquidBox = new LiquidBox();

        gaugeV2ALM = new GaugeV2ALM();
        liquidBoxFactory = new LiquidBoxFactory();

        lzMainChainId = uint16(100); //unreal
        lzPoolChainId = uint16(101); //arbirum

        lzEndPointMockL1 = new LZEndpointMock(lzMainChainId);
        nativeOFT = new OFTMockToken(address(lzEndPointMockL1));

        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        address voterProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 11);

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);

        votingEscrow = new VotingEscrow(address(nativeOFT));

        bytes memory init =
            abi.encodeCall(VotingEscrow.initialize, (address(vesting), address(voterProxyAddress), address(0)));

        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrow), init);
        votingEscrow = VotingEscrow(address(votingEscrowProxy));

        init = abi.encodeCall(LiquidBoxFactory.initialize, (address(this), pearlFactory, address(liquidBox)));

        ERC1967Proxy liquidBoxFactoryProxy = new ERC1967Proxy(address(liquidBoxFactory), init);

        liquidBoxFactory = LiquidBoxFactory(address(liquidBoxFactoryProxy));
        liquidBoxManager = new LiquidBoxManager();

        init = abi.encodeCall(
            LiquidBoxManager.initialize, (address(this), address(liquidBoxFactory), address(6), address(6))
        );

        ERC1967Proxy liquidBoxManagerProxy = new ERC1967Proxy(address(liquidBoxManager), init);

        liquidBoxManager = LiquidBoxManager(address(liquidBoxManagerProxy));
        mainChainId = block.chainid;

        address[] memory addr = new address[](1);
        addr[0] = address(nativeOFT);

        bribe = new Bribe();
        bribeFactoryL1 = new BribeFactory(mainChainId);

        init = abi.encodeCall(BribeFactory.initialize, (address(this), address(bribe), voterProxyAddress, ustb, addr));

        ERC1967Proxy bribeFactoryL1Proxy = new ERC1967Proxy(address(bribeFactoryL1), init);

        bribeFactoryL1 = BribeFactory(address(bribeFactoryL1Proxy));
        gaugeV2FactoryL1 = new GaugeV2Factory(mainChainId);

        init = abi.encodeCall(
            GaugeV2Factory.initialize,
            (
                address(this),
                address(gaugeV2),
                address(gaugeV2ALM),
                address(manager),
                address(liquidBoxManager),
                address(voterL1)
            )
        );

        ERC1967Proxy gaugeV2FactoryL1Proxy = new ERC1967Proxy(address(gaugeV2FactoryL1), init);

        gaugeV2FactoryL1 = GaugeV2Factory(address(gaugeV2FactoryL1Proxy));
        // pool = IPearlV2Factory(pearlFactory).getPool(dai, usdc, 1000);

        // voterL1 = new Voter(mainChainId, address(lzEndPointMockL1));

        // init = abi.encodeCall(
        //     Voter.initialize,
        //     (
        //         address(this),
        //         address(this),
        //         address(votingEscrow),
        //         address(nativeOFT),
        //         pearlFactory,
        //         address(gaugeV2FactoryL1),
        //         address(bribeFactoryL1),
        //         ustb,
        //         lzMainChainId,
        //         lzMainChainId
        //     )
        // );

        // ERC1967Proxy voterL1Proxy = new ERC1967Proxy(address(voterL1), init);
        // voterL1 = Voter(address(voterL1Proxy));

        // init = abi.encodeCall(
        //     Minter.initialize,
        //     (
        //         address(this),
        //         address(voterL1),
        //         address(votingEscrow),
        //         0xE7a23916706f8319395AC46a747983f9987cf942
        //     )
        // );

        // ERC1967Proxy minterProxy = new ERC1967Proxy(address(minter), init);
        // minter = Minter(address(minterProxy));

        // init = abi.encodeCall(
        //     EpochController.initialize,
        //     (address(this), address(minter), address(voterL1))
        // );
        // ERC1967Proxy epochControllerProxy = new ERC1967Proxy(
        //     address(epochController),
        //     init
        // );
        // epochController = EpochController(address(epochControllerProxy));

        // voterL1.setMinter(address(minter));
        // voterL1.setEpochController(address(epochController));

        // vm.startPrank(0x95e3664633A8650CaCD2c80A0F04fb56F65DF300);
        // IPearl(0xE7a23916706f8319395AC46a747983f9987cf942).setDepositor(
        //     address(minter)
        // );

        // IPearlV2Factory(pearlFactory).setGaugeManager(address(voterL1));
        // vm.stopPrank();

        // gaugeV2 = GaugeV2(
        //     payable(voterL1.createGauge{value: 0.1 ether}(pool, "0x"))
        // );

        // ######################### L2 Chain ########################################

        l2();
        // vm.chainId(mainChainId);
    }

    function l2() public {
        vm.chainId(42161);

        lzEndPointMockL2 = new LZEndpointMock(lzPoolChainId);
        otherOFT = new OFTMockToken(address(lzEndPointMockL2));

        address[] memory addr = new address[](1);
        addr[0] = address(otherOFT);

        gaugeV2L2 = new GaugeV2();
        liquidBoxL2 = new LiquidBox();
        gaugeV2ALML2 = new GaugeV2ALM();

        liquidBoxFactoryL2 = new LiquidBoxFactory();

        bytes memory init =
            abi.encodeCall(LiquidBoxFactory.initialize, (address(this), pearlFactory, address(liquidBoxL2)));

        ERC1967Proxy liquidBoxFactoryProxy = new ERC1967Proxy(address(liquidBoxFactoryL2), init);
        liquidBoxFactoryL2 = LiquidBoxFactory(address(liquidBoxFactoryProxy));

        liquidBoxManagerL2 = new LiquidBoxManager();
        init = abi.encodeCall(
            LiquidBoxManager.initialize, (address(this), address(liquidBoxFactoryL2), address(6), address(6))
        );

        ERC1967Proxy liquidBoxManagerProxy = new ERC1967Proxy(address(liquidBoxManagerL2), init);
        liquidBoxManagerL2 = LiquidBoxManager(address(liquidBoxManagerProxy));

        gaugeV2FactoryL2 = new GaugeV2Factory(mainChainId);

        init = abi.encodeCall(
            GaugeV2Factory.initialize,
            (
                address(this),
                address(gaugeV2L2),
                address(gaugeV2ALML2),
                address(manager),
                address(liquidBoxManagerL2),
                address(voterL2)
            )
        );

        ERC1967Proxy gaugeV2FactoryL2Proxy = new ERC1967Proxy(address(gaugeV2FactoryL2), init);

        gaugeV2FactoryL2 = GaugeV2Factory(address(gaugeV2FactoryL2Proxy));

        address voterProxyAddressL2 = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);

        bribeFactoryL2 = new BribeFactory(mainChainId);

        init = abi.encodeCall(BribeFactory.initialize, (address(this), address(bribe), voterProxyAddressL2, ustb, addr));
        ERC1967Proxy bribeFactoryL2Proxy = new ERC1967Proxy(address(bribeFactoryL2), init);

        bribeFactoryL2 = BribeFactory(address(bribeFactoryL2Proxy));
        voterL2 = new Voter(mainChainId, address(lzEndPointMockL2));

        init = abi.encodeCall(
            Voter.initialize,
            (
                address(this),
                address(this),
                address(0),
                address(otherOFT),
                pearlFactory,
                address(gaugeV2FactoryL2),
                address(bribeFactoryL2),
                ustb,
                lzMainChainId,
                lzPoolChainId
            )
        );

        ERC1967Proxy voterL2Proxy = new ERC1967Proxy(address(voterL2), init);
        voterL2 = Voter(address(voterL2Proxy));

        // vm.startPrank(0x95e3664633A8650CaCD2c80A0F04fb56F65DF300);
        // IPearlV2Factory(pearlFactory).setGaugeManager(address(voterL2));
        // vm.stopPrank();

        // lzEndPointMockL1.setDestLzEndpoint(
        //     address(voterL2),
        //     address(lzEndPointMockL2)
        // );
        // lzEndPointMockL2.setDestLzEndpoint(
        //     address(voterL1),
        //     address(lzEndPointMockL1)
        // );

        // lzEndPointMockL1.setDestLzEndpoint(
        //     address(otherOFT),
        //     address(lzEndPointMockL2)
        // );
        // lzEndPointMockL2.setDestLzEndpoint(
        //     address(nativeOFT),
        //     address(lzEndPointMockL1)
        // );

        // nativeOFT.setTrustedRemoteAddress(
        //     lzPoolChainId,
        //     abi.encodePacked(address(otherOFT))
        // );
        // otherOFT.setTrustedRemoteAddress(
        //     lzMainChainId,
        //     abi.encodePacked(address(nativeOFT))
        // );

        // voterL1.setTrustedRemote(
        //     lzPoolChainId,
        //     abi.encodePacked(address(voterL2), address(voterL1))
        // );
        // voterL2.setTrustedRemote(
        //     lzMainChainId,
        //     abi.encodePacked(address(voterL1), address(voterL2))
        // );

        // poolL2 = 0x3dDc6EbfB3BB43aDAED7Ef1Aaae75fAD8caa3419;

        // assertEq(voterL1.getLzPoolsLength(), 0);
        // gaugeV2L2 = GaugeV2(
        //     payable(voterL2.createGauge{value: 10 ether}(poolL2, ""))
        // );

        // assertEq(voterL1.getLzPoolsLength(), 1);
    }

    // function test_deposit() public {
    // (uint256 tokenId, uint128 liquidityToAdd,,) = mintNewPosition(1 ether, 1 ether);

    // IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);

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

    // function test_claim_reward() public {
    //     vote(pool);
    //     (uint256 tokenId, , , ) = mintNewPosition(1 ether, 1 ether);

    //     vm.warp(block.timestamp + minter.nextPeriod());
    //     epochController.distribute();

    //     IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);

    //     gaugeV2.deposit(tokenId);
    //     console.log(nativeOFT.balanceOf(address(this)), "before");

    //     vm.warp(block.timestamp + 1 hours);

    //     gaugeV2.collectReward(tokenId);
    //     console.log(nativeOFT.balanceOf(address(this)), "after");
    // }

    function test_distribution() public {
        // vote(pool);

        // console.log(nativeOFT.balanceOf(address(this)), "before");

        // vm.warp(block.timestamp + minter.nextPeriod());
        // epochController.distribute();
        // console.log(nativeOFT.balanceOf(address(this)), "after");
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

    // function test_withdraw() public {
    //     (uint256 tokenId, uint128 liquidityToAdd, , ) = mintNewPosition(
    //         1 ether,
    //         1 ether
    //     );

    //     IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);
    //     gaugeV2.deposit(tokenId);

    //     assertEq(gaugeV2.stakedBalance(address(this)), 1);
    //     gaugeV2.withdraw(tokenId, address(this), "0x");

    //     (, uint256 liquidityAdded, , ) = gaugeV2.stakePos(
    //         keccak256(abi.encodePacked(address(this), tokenId))
    //     );

    //     assertEq(0, liquidityAdded);
    //     assertEq(gaugeV2.stakedBalance(address(this)), 0);
    // }

    // event IncreaseLiquidity(
    //     address indexed user,
    //     uint256 tokenId,
    //     uint128 liquidity
    // );

    // function test_increaseLiquidity() public {
    //     (uint256 tokenId, uint128 liquidityToAdd, , ) = mintNewPosition(
    //         1 ether,
    //         1 ether
    //     );

    //     IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);
    //     gaugeV2.deposit(tokenId);

    //     vm.startPrank(usdcHolder);
    //     IERC20(usdc).transfer(address(this), 1 ether);
    //     vm.stopPrank();

    //     vm.startPrank(daiHolder);
    //     IERC20(dai).transfer(address(this), 1 ether);
    //     vm.stopPrank();

    //     IERC20(dai).approve(address(gaugeV2), 1 ether);
    //     IERC20(usdc).approve(address(gaugeV2), 1 ether);

    //     //Todo: assert liquidityToBeAdded is correct

    //     // uint256 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
    //     //     sqrtP(currentPrice),
    //     //     sqrtP60FromTick(lowerTick),
    //     //     sqrtP60FromTick(upperTick),
    //     //     params.amount0Desired,
    //     //     params.amount1Desired
    //     // );

    //     INonfungiblePositionManager.IncreaseLiquidityParams
    //         memory params = INonfungiblePositionManager
    //             .IncreaseLiquidityParams({
    //                 tokenId: tokenId,
    //                 amount0Desired: 1 ether,
    //                 amount1Desired: 1 ether,
    //                 amount0Min: 0,
    //                 amount1Min: 0,
    //                 deadline: block.timestamp
    //             });

    //     // vm.expectEmit(true, true, false, true);
    //     // emit IncreaseLiquidity(
    //     //     address(this),
    //     //     tokenId,
    //     //     1998999749874 - 999499874937
    //     // );

    //     (, uint128 liquidity, , ) = gaugeV2.stakePos(
    //         keccak256(abi.encodePacked(address(this), tokenId))
    //     );

    //     gaugeV2.increaseLiquidity(params);

    //     (, liquidityToAdd, , ) = gaugeV2.stakePos(
    //         keccak256(abi.encodePacked(address(this), tokenId))
    //     );

    //     // assertEq(liquidityToAdd, liquidity + (1998999749874 - 999499874937));

    //     //Todo:replace 1998999749874 - 999499874937 with liquidityToBeAdded
    // }

    // function test_decreaseLiquidity() public {
    //     (uint256 tokenId, uint128 liquidityToAdd, , ) = mintNewPosition(
    //         1 ether,
    //         1 ether
    //     );

    //     IERC721(pearlPositionNFT).approve(address(gaugeV2), tokenId);
    //     gaugeV2.deposit(tokenId);

    //     INonfungiblePositionManager.DecreaseLiquidityParams
    //         memory params = INonfungiblePositionManager
    //             .DecreaseLiquidityParams({
    //                 tokenId: tokenId,
    //                 liquidity: liquidityToAdd,
    //                 amount0Min: 0,
    //                 amount1Min: 0,
    //                 deadline: block.timestamp
    //             });
    //     (address owner, uint128 liquidityAdded, , ) = gaugeV2.stakePos(
    //         keccak256(abi.encodePacked(address(this), tokenId))
    //     );

    //     assertEq(liquidityToAdd, liquidityAdded);
    //     assertEq(gaugeV2.stakedBalance(address(this)), 1);

    //     gaugeV2.decreaseLiquidity(params);

    //     (owner, liquidityAdded, , ) = gaugeV2.stakePos(
    //         keccak256(abi.encodePacked(address(this), tokenId))
    //     );

    //     assertEq(liquidityAdded, 0);
    // }

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

    // function mintNewPosition2(
    //     uint256 amount0ToAdd,
    //     uint256 amount1ToAdd
    // )
    //     private
    //     returns (
    //         uint256 tokenId,
    //         uint128 liquidity,
    //         uint256 amount0,
    //         uint256 amount1
    //     )
    // {
    //     vm.startPrank(usdcHolder);
    //     IERC20(usdc).transfer(address(this), amount1ToAdd);
    //     vm.stopPrank();

    //     vm.startPrank(daiHolder);
    //     IERC20(dai).transfer(address(this), amount1ToAdd);
    //     vm.stopPrank();

    //     IERC20(dai).approve(address(manager), amount0ToAdd);
    //     IERC20(usdc).approve(address(manager), amount1ToAdd);

    //     INonfungiblePositionManager.MintParams
    //         memory params = INonfungiblePositionManager.MintParams({
    //             token0: dai,
    //             token1: usdc,
    //             fee: 1000,
    //             tickLower: -276540,
    //             tickUpper: -276140,
    //             amount0Desired: amount0ToAdd,
    //             amount1Desired: amount1ToAdd,
    //             amount0Min: 0,
    //             amount1Min: 0,
    //             recipient: address(this),
    //             deadline: block.timestamp
    //         });

    //     (tokenId, liquidity, amount0, amount1) = manager.mint(params);
    // }

    // function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd)
    //     private
    //     returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    // {
    //     deal(address(dai), address(this), amount1ToAdd);
    //     deal(address(usdc), address(this), amount0ToAdd);

    //     IERC20(dai).approve(address(manager), amount0ToAdd);
    //     IERC20(usdc).approve(address(manager), amount1ToAdd);

    //     INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
    //         token0: dai,
    //         token1: usdc,
    //         fee: 1000,
    //         tickLower: -276540,
    //         tickUpper: -276140,
    //         amount0Desired: amount0ToAdd,
    //         amount1Desired: amount1ToAdd,
    //         amount0Min: 0,
    //         amount1Min: 0,
    //         recipient: address(this),
    //         deadline: block.timestamp
    //     });

    //     (tokenId, liquidity, amount0, amount1) = manager.mint(params);
    // }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
