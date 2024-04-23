// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./utils/Imports.sol";

/**
 * @title Uint Test For GaugeV2 Contract
 * @author c-n-o-t-e
 * @dev Contract is used to test out BribeFactory Contract
 *
 * Functionalities Tested: All external/public functions.
 */

contract GaugeInvariantTest is Imports {
    function setUp() public {
        l1SetUp();
    }

    function test_AssertInitialization() public {
        assertEq(bribeFactory.keeper(), address(this));
        assertEq(bribeFactory.voter(), address(voterL1));
        assertEq(bribeFactory.ustb(), address(nativeOFT));
        assertEq(bribeFactory.bribeAdmin(), address(this));
        assertEq(bribeFactory.defaultRewardToken(0), address(nativeOFT));
        assertEq(bribeFactory.isDefaultRewardToken(address(nativeOFT)), true);
    }

    function testShouldCreateBribe() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(3), address(6), "_type"
        );

        assertEq(bribeFactory.recentBribe(), bribe);
        assertEq(Bribe(bribe).rewardTokens(1), address(3));

        assertEq(Bribe(bribe).rewardTokens(2), address(6));
        assertEq(Bribe(bribe).rewardTokens(0), address(nativeOFT));
    }

    function testShouldSetVoter() public {
        address newVoter = makeAddr("newVoter");
        bribeFactory.setVoter(newVoter);
        assertEq(bribeFactory.voter(), newVoter);
    }

    function testShouldSetKeeper() public {
        address newKeeper = makeAddr("newKeeper");
        bribeFactory.setKeeper(newKeeper);
        assertEq(bribeFactory.keeper(), newKeeper);
    }

    function testShouldSetBribeImplementation() public {
        address newBribeImplementation = makeAddr("newBribeImplementation");
        bribeFactory.setBribeImplementation(newBribeImplementation);
        assertEq(bribeFactory.bribeImplementation(), newBribeImplementation);
    }

    function testShouldAddDefaultRewardToken() public {
        address newToken = makeAddr("newToken");
        bribeFactory.pushDefaultRewardToken(newToken);

        assertEq(bribeFactory.defaultRewardToken(1), newToken);
        assertEq(bribeFactory.isDefaultRewardToken(newToken), true);
    }

    function testShouldRemoveDefaultRewardToken() public {
        address newToken = makeAddr("newToken");
        address newToken0 = makeAddr("newToken0");

        bribeFactory.pushDefaultRewardToken(newToken);
        bribeFactory.pushDefaultRewardToken(newToken0);

        assertEq(bribeFactory.defaultRewardToken(1), newToken);
        assertEq(bribeFactory.isDefaultRewardToken(newToken), true);

        bribeFactory.removeDefaultRewardToken(newToken);
        assertEq(bribeFactory.defaultRewardToken(1), newToken0);
        assertEq(bribeFactory.isDefaultRewardToken(newToken), false);
    }

    function testShouldFailIfAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Zero_Address_Not_Allowed.selector));
        bribeFactory.pushDefaultRewardToken(address(0));

        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Zero_Address_Not_Allowed.selector));
        bribeFactory.setBribeAdmin(address(0));

        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Zero_Address_Not_Allowed.selector));
        bribeFactory.setVoter(address(0));

        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Zero_Address_Not_Allowed.selector));
        bribeFactory.setKeeper(address(0));

        vm.expectRevert("!zero address");
        bribeFactory.setBribeImplementation(address(0));

        address[] memory addr = new address[](1);
        addr[0] = address(nativeOFT);

        BribeFactory b = new BribeFactory(mainChainId);

        bytes memory init =
            abi.encodeCall(BribeFactory.initialize, (address(this), address(0), address(0), address(0), addr));

        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Zero_Address_Not_Allowed.selector));
        new ERC1967Proxy(address(b), init);

        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(bribeFactory), address(3), address(6), "_type"
        );

        address[] memory bribes = new address[](1);
        bribes[0] = bribe;

        vm.expectRevert("!voter");
        bribeFactory.setBribeVoter(bribes, address(0));

        vm.expectRevert("!minter");
        bribeFactory.setBribeMinter(bribes, address(0));

        vm.expectRevert("!owner");
        bribeFactory.setBribeOwner(bribes, address(0));
    }

    function testShouldFailIfTokenAlreadyExist() public {
        address newToken = makeAddr("newToken");
        bribeFactory.pushDefaultRewardToken(newToken);

        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Token_Already_Added.selector));
        bribeFactory.pushDefaultRewardToken(newToken);
    }

    function testShouldSetBribeAdmin() public {
        assertEq(bribeFactory.bribeAdmin(), address(this));
        bribeFactory.setBribeAdmin(address(1));
        assertEq(bribeFactory.bribeAdmin(), address(1));
    }

    function testShouldFailIfTokenIsNotRewardToken() public {
        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Not_A_Default_Reward_Token.selector));
        bribeFactory.removeDefaultRewardToken(makeAddr("newToken"));
    }

    function testShouldFailIfNotOwnerOrVoter() public {
        vm.startPrank(address(9));
        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_NotAuthorized.selector));

        bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(3), address(3), "_type"
        );

        vm.stopPrank();
    }

    function testShouldFailIfTokenIsTheSame() public {
        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Tokens_Cannot_Be_The_Same.selector));

        bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(3), address(3), "_type"
        );
    }

    function testShouldAddRewardTokenToBribeContract() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );

        bribeFactory.addRewardToBribe(makeAddr("rewardToken"), bribe);
        assertEq(Bribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
    }

    function testShouldAddRewardTokensToBribeContract() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );

        address[] memory addr = new address[](2);
        addr[0] = makeAddr("rewardToken");

        addr[1] = makeAddr("rewardToken1");
        bribeFactory.addRewardsToBribe(addr, bribe);

        assertEq(Bribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(Bribe(bribe).rewardTokens(2), makeAddr("rewardToken1"));
    }

    function testShouldAddRewardTokenToBribeContractsWhenCreated() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId,
            lzMainChainId,
            address(1),
            address(this),
            makeAddr("rewardToken"),
            makeAddr("rewardToken0"),
            "_type"
        );

        assertEq(bribeFactory.recentBribe(), bribe);
        assertEq(Bribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(Bribe(bribe).rewardTokens(2), makeAddr("rewardToken0"));
    }

    function testShouldSetConvertData() public {
        (address target, bytes4 selc) = bribeFactory.convertData(address(1));
        assertEq(selc, 0x0);

        bytes4 selector = bytes4(keccak256(bytes("functionName(uint256,address,address)")));
        bribeFactory.setConvertData(address(1), selector);

        (target, selc) = bribeFactory.convertData(address(1));
        assertEq(selc, selector);
    }

    function testShouldAddRewardTokenToBribeContracts() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );

        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(this), address(0), address(0), "_type"
        );

        assertEq(bribeFactory.recentBribe(), bribe0);

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        bribeFactory.addRewardToBribes(makeAddr("rewardToken"), bribes);

        assertEq(Bribe(bribes[0]).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(Bribe(bribes[1]).rewardTokens(1), makeAddr("rewardToken"));
    }

    function testShouldAddRewardsTokenToBribeContracts() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(bribeFactory), address(0), address(0), "_type"
        );

        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(bribeFactory), address(0), address(0), "_type"
        );

        address[] memory bribes = new address[](2);

        bribes[0] = bribe;
        bribes[1] = bribe0;

        address[][] memory rewards = new address[][](2);
        rewards[0] = new address[](2);
        rewards[1] = new address[](2);

        rewards[0][0] = makeAddr("rewardToken");
        rewards[0][1] = makeAddr("rewardToken0");

        rewards[1][0] = makeAddr("rewardToken");
        rewards[1][1] = makeAddr("rewardToken0");

        bribeFactory.addRewardsToBribes(rewards, bribes);

        assertEq(Bribe(bribe).rewardTokens(0), address(nativeOFT));
        assertEq(Bribe(bribe0).rewardTokens(0), address(nativeOFT));

        assertEq(Bribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(Bribe(bribe0).rewardTokens(1), makeAddr("rewardToken"));

        assertEq(Bribe(bribe).rewardTokens(2), makeAddr("rewardToken0"));
        assertEq(Bribe(bribe0).rewardTokens(2), makeAddr("rewardToken0"));
    }

    function testShouldSetBribeVoter() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );
        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(this), address(0), address(0), "_type"
        );

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        assertEq(Bribe(bribe).voter(), address(voterL1));
        assertEq(Bribe(bribe0).voter(), address(voterL1));

        bribeFactory.setBribeVoter(bribes, makeAddr("voter"));

        assertEq(Bribe(bribe).voter(), makeAddr("voter"));
        assertEq(Bribe(bribe0).voter(), makeAddr("voter"));
    }

    function testShouldSetBribeMinter() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );
        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(this), address(0), address(0), "_type"
        );

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        assertEq(Bribe(bribe).minter(), address(minter));
        assertEq(Bribe(bribe0).minter(), address(minter));

        bribeFactory.setBribeMinter(bribes, makeAddr("minter"));

        assertEq(Bribe(bribe).minter(), makeAddr("minter"));
        assertEq(Bribe(bribe0).minter(), makeAddr("minter"));
    }

    function testShouldSetBribeOwner() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(bribeFactory), address(0), address(0), "_type"
        );
        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(bribeFactory), address(0), address(0), "_type"
        );

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        assertEq(Bribe(bribe).owner(), address(bribeFactory));
        assertEq(Bribe(bribe0).owner(), address(bribeFactory));

        bribeFactory.setBribeOwner(bribes, makeAddr("owner0"));

        assertEq(Bribe(bribe).owner(), makeAddr("owner0"));
        assertEq(Bribe(bribe0).owner(), makeAddr("owner0"));
    }

    function testShouldRecoverERC20From() public {
        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );
        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(this), address(0), address(0), "_type"
        );

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        OFTMockToken nativeOFT0 = new OFTMockToken(address(lzEndPointMockL1));

        nativeOFT.mint(bribe, 1 ether);
        nativeOFT.mint(bribe0, 1 ether);

        nativeOFT0.mint(bribe, 1 ether);

        address[][] memory tokens = new address[][](2);
        tokens[0] = new address[](2);
        tokens[1] = new address[](1);

        tokens[0][0] = address(nativeOFT);
        tokens[0][1] = address(nativeOFT0);

        tokens[1][0] = address(nativeOFT);

        uint256[][] memory amounts = new uint256[][](2);
        amounts[0] = new uint256[](2);
        amounts[1] = new uint256[](1);

        amounts[0][0] = 0.5 ether;
        amounts[0][1] = 0.7 ether;

        amounts[1][0] = 0.6 ether;

        assertEq(nativeOFT.balanceOf(bribe), 1 ether);
        assertEq(nativeOFT0.balanceOf(bribe), 1 ether);
        assertEq(nativeOFT.balanceOf(bribe0), 1 ether);

        bribeFactory.recoverERC20From(bribes, tokens, amounts, false);

        assertEq(nativeOFT.balanceOf(bribe), 0.5 ether);
        assertEq(nativeOFT0.balanceOf(bribe), 0.3 ether);
        assertEq(nativeOFT.balanceOf(bribe0), 0.4 ether);
    }

    function testShouldrecoverERC20AndUpdateData() public {
        OFTMockToken nativeOFT0 = new OFTMockToken(address(lzEndPointMockL1));

        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(nativeOFT0), address(0), "_type"
        );
        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(this), address(0), address(0), "_type"
        );

        nativeOFT.mint(address(this), 2 ether);
        nativeOFT0.mint(address(this), 1 ether);

        nativeOFT.approve(bribe, 1 ether);
        nativeOFT0.approve(bribe, 1 ether);

        nativeOFT.approve(bribe0, 1 ether);
        address[] memory bribes = new address[](2);

        bribes[0] = bribe;
        bribes[1] = bribe0;

        bribeFactory.setBribeMinter(bribes, address(minter));
        Bribe(bribe).notifyRewardAmount(address(nativeOFT), 1 ether);

        Bribe(bribe).notifyRewardAmount(address(nativeOFT0), 1 ether);
        Bribe(bribe0).notifyRewardAmount(address(nativeOFT), 1 ether);

        address[][] memory tokens = new address[][](2);
        tokens[0] = new address[](2);
        tokens[1] = new address[](1);

        tokens[0][0] = address(nativeOFT);
        tokens[0][1] = address(nativeOFT0);
        tokens[1][0] = address(nativeOFT);

        uint256[][] memory amounts = new uint256[][](2);
        amounts[0] = new uint256[](2);

        amounts[1] = new uint256[](1);
        amounts[0][0] = 0.5 ether;

        amounts[0][1] = 0.7 ether;
        amounts[1][0] = 0.6 ether;

        assertEq(nativeOFT.balanceOf(bribe), 1 ether);
        assertEq(nativeOFT0.balanceOf(bribe), 1 ether);
        assertEq(nativeOFT.balanceOf(bribe0), 1 ether);

        bribeFactory.recoverERC20From(bribes, tokens, amounts, true);

        assertEq(nativeOFT.balanceOf(bribe), 0.5 ether);
        assertEq(nativeOFT0.balanceOf(bribe), 0.3 ether);
        assertEq(nativeOFT.balanceOf(bribe0), 0.4 ether);
    }

    function testShouldFailIfTokenLengthIsNotEqualToAmountLength() public {
        OFTMockToken nativeOFT0 = new OFTMockToken(address(lzEndPointMockL1));

        address bribe = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(1), address(this), address(0), address(0), "_type"
        );
        address bribe0 = bribeFactory.createBribe(
            lzMainChainId, lzMainChainId, address(2), address(this), address(0), address(0), "_type"
        );

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        nativeOFT.mint(bribe, 1 ether);
        nativeOFT.mint(bribe0, 1 ether);

        nativeOFT0.mint(bribe0, 1 ether);

        address[][] memory tokens = new address[][](2);
        tokens[0] = new address[](1);
        tokens[1] = new address[](2);

        tokens[0][0] = address(nativeOFT);

        tokens[1][0] = address(nativeOFT);
        tokens[1][1] = address(nativeOFT0);

        uint256[][] memory amounts = new uint256[][](2);
        amounts[0] = new uint256[](1);
        amounts[1] = new uint256[](1);

        amounts[0][0] = 0.5 ether;
        amounts[1][0] = 0.6 ether;

        vm.expectRevert(abi.encodeWithSelector(BribeFactory.BribeFactory_Mismatch_Length.selector));
        bribeFactory.recoverERC20From(bribes, tokens, amounts, false);
    }
}
