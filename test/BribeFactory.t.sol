// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Voter} from "../src/Voter.sol";
import {Minter} from "../src/v1.5/Minter.sol";
import {IBribe} from "../src/interfaces/IBribe.sol";
import {IPearl} from "../src/interfaces/IPearl.sol";
import {Pearl} from "pearl-token/src/token/Pearl.sol";
import {BribeFactory} from "../src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";

/**
 * @title Uint Test For Bribe Factory Contract
 * @author c-n-o-t-e
 * @dev
 *
 *
 */

contract BribeFactoryTest is Test {
    error BribeFactory_Token_Already_Added();
    error BribeFactory_Zero_Address_Not_Allowed();
    error BribeFactory_Tokens_Cannot_Be_The_Same();
    error BribeFactory_Not_A_Default_Reward_Token();

    Voter public voter;
    Pearl public pearl;
    Minter public minter;
    BribeFactory public bribeFactory;
    VotingEscrowVesting vesting;

    function setUp() public {
        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 6);

        address factoryProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 8);

        pearl = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearl.initialize, (address(7)));

        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearl), init);
        pearl = Pearl(address(pearlProxy));

        VotingEscrow votingEscrowImpl = new VotingEscrow(address(pearlProxy));
        voter = new Voter();

        init =
            abi.encodeCall(voter.initialize, (address(votingEscrowImpl), address(1), address(2), factoryProxyAddress));
        ERC1967Proxy voterProxy = new ERC1967Proxy(address(voter), init);
        voter = Voter(address(voterProxy));

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);

        init = abi.encodeCall(votingEscrowImpl.initialize, (address(vesting), address(5), address(0)));

        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrowImpl), init);

        address[] memory addr = new address[](1);
        addr[0] = address(pearl);

        voter.setVotingEscrow(address(votingEscrowProxy));
        voter._initialize(addr, address(8));

        bribeFactory = new BribeFactory();

        init = abi.encodeCall(BribeFactory.initialize, (address(voter), addr));

        ERC1967Proxy mainProxy = new ERC1967Proxy(address(bribeFactory), init);
        bribeFactory = BribeFactory(address(mainProxy));

        minter = new Minter();

        init = abi.encodeCall(Minter.initialize, (address(voter), address(votingEscrowProxy), address(88)));

        ERC1967Proxy minterProxy = new ERC1967Proxy(address(minter), init);
        minter = Minter(address(minterProxy));
    }

    function test_AssertInitialization() public {
        assertEq(bribeFactory.voter(), address(voter));
        assertEq(bribeFactory.hasRole(0x00, address(this)), true);

        assertEq(bribeFactory.defaultRewardToken(0), address(pearl));
        assertEq(bribeFactory.isDefaultRewardToken(address(pearl)), true);

        assertEq(bribeFactory.hasRole(keccak256("BRIBE_ADMIN"), address(this)), true);
    }

    //////////////////////////////////  ONLY OWNER INTERACTIONS //////////////////////////////////

    function test_BribeDeployment() public {
        address bribe = bribeFactory.createBribe(address(1), address(3), address(6), "_type");
        assertEq(bribeFactory.last_bribe(), bribe);
    }

    function test_SetVoter() public {
        address newVoter = makeAddr("newVoter");
        bribeFactory.setVoter(newVoter);
        assertEq(bribeFactory.voter(), newVoter);
    }

    function test_AddDefaultRewardToken() public {
        address newToken = makeAddr("newToken");
        bribeFactory.pushDefaultRewardToken(newToken);

        assertEq(bribeFactory.defaultRewardToken(1), newToken);
        assertEq(bribeFactory.isDefaultRewardToken(newToken), true);
    }

    function test_RemoveDefaultRewardToken() public {
        address newToken = makeAddr("newToken");
        bribeFactory.pushDefaultRewardToken(newToken);

        assertEq(bribeFactory.defaultRewardToken(0), address(pearl));
        bribeFactory.removeDefaultRewardToken(address(pearl));

        assertEq(bribeFactory.defaultRewardToken(0), newToken);
        assertEq(bribeFactory.isDefaultRewardToken(address(pearl)), false);
    }

    function test_ShouldFailIfAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(BribeFactory_Zero_Address_Not_Allowed.selector));
        bribeFactory.pushDefaultRewardToken(address(0));

        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory bribes = new address[](1);
        bribes[0] = bribe;

        vm.expectRevert();
        bribeFactory.setBribeVoter(bribes, address(0));

        vm.expectRevert();
        bribeFactory.setBribeMinter(bribes, address(0));

        vm.expectRevert();
        bribeFactory.setBribeOwner(bribes, address(0));
    }

    function test_ShouldFailIfTokenAlreadyExist() public {
        address newToken = makeAddr("newToken");
        bribeFactory.pushDefaultRewardToken(newToken);

        vm.expectRevert(abi.encodeWithSelector(BribeFactory_Token_Already_Added.selector));
        bribeFactory.pushDefaultRewardToken(newToken);
    }

    function test_ShouldFailIfTokenIsNotRewardToken() public {
        vm.expectRevert(abi.encodeWithSelector(BribeFactory_Not_A_Default_Reward_Token.selector));
        bribeFactory.removeDefaultRewardToken(makeAddr("newToken"));
    }

    function test_ShouldFailIfTokenIsTheSame() public {
        vm.expectRevert(abi.encodeWithSelector(BribeFactory_Tokens_Cannot_Be_The_Same.selector));

        bribeFactory.createBribe(address(1), address(3), address(3), "_type");
    }

    ////////////////////////////////// ONLY OWNER or BRIBE ADMIN INTERACTIONS //////////////////////////////////

    function test_ShouldAddRewardTokenToBrideContract() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        bribeFactory.addRewardToBribe(makeAddr("rewardToken"), bribe);
        assertEq(IBribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
    }

    function test_ShouldAddRewardTokensToBrideContract() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory addr = new address[](2);
        addr[0] = makeAddr("rewardToken");

        addr[1] = makeAddr("rewardToken1");
        bribeFactory.addRewardsToBribe(addr, bribe);

        assertEq(IBribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(IBribe(bribe).rewardTokens(2), makeAddr("rewardToken1"));
    }

    function test_ShouldAddRewardTokenToBrideContracts() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        bribeFactory.addRewardToBribes(makeAddr("rewardToken"), bribes);

        assertEq(IBribe(bribes[0]).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(IBribe(bribes[1]).rewardTokens(1), makeAddr("rewardToken"));
    }

    function test_ShouldAddRewardsTokenToBrideContracts() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

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

        assertEq(IBribe(bribe).rewardTokens(0), address(pearl));
        assertEq(IBribe(bribe0).rewardTokens(0), address(pearl));

        assertEq(IBribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(IBribe(bribe0).rewardTokens(1), makeAddr("rewardToken"));

        assertEq(IBribe(bribe).rewardTokens(2), makeAddr("rewardToken0"));
        assertEq(IBribe(bribe0).rewardTokens(2), makeAddr("rewardToken0"));
    }

    function test_ShouldSetBribeVoter() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        assertEq(IBribe(bribe).voter(), address(voter));
        assertEq(IBribe(bribe0).voter(), address(voter));

        bribeFactory.setBribeVoter(bribes, makeAddr("voter"));

        assertEq(IBribe(bribe).voter(), makeAddr("voter"));
        assertEq(IBribe(bribe0).voter(), makeAddr("voter"));
    }

    function test_ShouldSetBribeMinter() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        assertEq(IBribe(bribe).minter(), address(8));
        assertEq(IBribe(bribe0).minter(), address(8));

        bribeFactory.setBribeMinter(bribes, makeAddr("minter"));

        assertEq(IBribe(bribe).minter(), makeAddr("minter"));
        assertEq(IBribe(bribe0).minter(), makeAddr("minter"));
    }

    function test_ShouldSetBribeOwner() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        assertEq(IBribe(bribe).owner(), makeAddr("owner"));
        assertEq(IBribe(bribe0).owner(), makeAddr("owner"));

        bribeFactory.setBribeOwner(bribes, makeAddr("owner0"));

        assertEq(IBribe(bribe).owner(), makeAddr("owner0"));
        assertEq(IBribe(bribe0).owner(), makeAddr("owner0"));
    }

    function test_ShouldRecoverERC20From() public {
        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        Pearl pearl0 = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearl0.initialize, (address(7)));

        ERC1967Proxy pearl0Proxy = new ERC1967Proxy(address(pearl0), init);
        pearl0 = Pearl(address(pearl0Proxy));

        pearl.mint(bribe, 1 ether);
        pearl.mint(bribe0, 1 ether);

        pearl0.mint(bribe, 1 ether);

        address[][] memory tokens = new address[][](2);
        tokens[0] = new address[](2);
        tokens[1] = new address[](1);

        tokens[0][0] = address(pearl);
        tokens[0][1] = address(pearl0);

        tokens[1][0] = address(pearl);

        uint256[][] memory amounts = new uint256[][](2);
        amounts[0] = new uint256[](2);
        amounts[1] = new uint256[](1);

        amounts[0][0] = 0.5 ether;
        amounts[0][1] = 0.7 ether;

        amounts[1][0] = 0.6 ether;

        assertEq(IPearl(address(pearl)).balanceOf(bribe), 1 ether);
        assertEq(IPearl(address(pearl0)).balanceOf(bribe), 1 ether);
        assertEq(IPearl(address(pearl)).balanceOf(bribe0), 1 ether);

        bribeFactory.recoverERC20From(bribes, tokens, amounts);

        assertEq(IPearl(address(pearl)).balanceOf(bribe), 0.5 ether);
        assertEq(IPearl(address(pearl0)).balanceOf(bribe), 0.3 ether);
        assertEq(IPearl(address(pearl)).balanceOf(bribe0), 0.4 ether);
    }

    function test_ShouldrecoverERC20AndUpdateData() public {
        Pearl pearl0 = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearl0.initialize, (address(7)));

        ERC1967Proxy pearl0Proxy = new ERC1967Proxy(address(pearl0), init);
        pearl0 = Pearl(address(pearl0Proxy));

        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(pearl0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        pearl.mint(address(this), 2 ether);
        pearl0.mint(address(this), 1 ether);

        IPearl(address(pearl)).approve(bribe, 1 ether);
        IPearl(address(pearl0)).approve(bribe, 1 ether);

        IPearl(address(pearl)).approve(bribe0, 1 ether);
        address[] memory bribes = new address[](2);

        bribes[0] = bribe;
        bribes[1] = bribe0;

        bribeFactory.setBribeMinter(bribes, address(minter));
        IBribe(bribe).notifyRewardAmount(address(pearl), 1 ether);

        IBribe(bribe).notifyRewardAmount(address(pearl0), 1 ether);
        IBribe(bribe0).notifyRewardAmount(address(pearl), 1 ether);

        address[][] memory tokens = new address[][](2);
        tokens[0] = new address[](2);
        tokens[1] = new address[](1);

        tokens[0][0] = address(pearl);
        tokens[0][1] = address(pearl0);
        tokens[1][0] = address(pearl);

        uint256[][] memory amounts = new uint256[][](2);
        amounts[0] = new uint256[](2);

        amounts[1] = new uint256[](1);
        amounts[0][0] = 0.5 ether;

        amounts[0][1] = 0.7 ether;
        amounts[1][0] = 0.6 ether;

        assertEq(IPearl(address(pearl)).balanceOf(bribe), 1 ether);
        assertEq(IPearl(address(pearl0)).balanceOf(bribe), 1 ether);
        assertEq(IPearl(address(pearl)).balanceOf(bribe0), 1 ether);

        bribeFactory.recoverERC20From(bribes, tokens, amounts);

        assertEq(IPearl(address(pearl)).balanceOf(bribe), 0.5 ether);
        assertEq(IPearl(address(pearl0)).balanceOf(bribe), 0.3 ether);
        assertEq(IPearl(address(pearl)).balanceOf(bribe0), 0.4 ether);
    }

    function test_ShouldFailIfTokenLengthIsNotEqualToAmountLength() public {
        Pearl pearl0 = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearl0.initialize, (address(7)));

        ERC1967Proxy pearl0Proxy = new ERC1967Proxy(address(pearl0), init);
        pearl0 = Pearl(address(pearl0Proxy));

        address bribe = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");
        address bribe0 = bribeFactory.createBribe(makeAddr("owner"), address(0), address(0), "_type");

        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        pearl.mint(bribe, 1 ether);
        pearl.mint(bribe0, 1 ether);

        pearl0.mint(bribe0, 1 ether);

        address[][] memory tokens = new address[][](2);
        tokens[0] = new address[](1);
        tokens[1] = new address[](2);

        tokens[0][0] = address(pearl);

        tokens[1][0] = address(pearl);
        tokens[1][1] = address(pearl0);

        uint256[][] memory amounts = new uint256[][](2);
        amounts[0] = new uint256[](1);
        amounts[1] = new uint256[](1);

        amounts[0][0] = 0.5 ether;
        amounts[1][0] = 0.6 ether;

        vm.expectRevert("mismatch len");
        bribeFactory.recoverERC20From(bribes, tokens, amounts);
    }
}
