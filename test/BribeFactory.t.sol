// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Voter} from "../src/Voter.sol";
import {Pearl} from "pearl-token/src/token/Pearl.sol";
import {IBribe} from "../src/interfaces/IBribe.sol";
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
    BribeFactory public bribeFactory;
    VotingEscrowVesting vesting;

    function setUp() public {
        address votingEscrowProxyAddress = vm.computeCreateAddress(
            address(this),
            vm.getNonce(address(this)) + 6
        );

        address factoryProxyAddress = vm.computeCreateAddress(
            address(this),
            vm.getNonce(address(this)) + 8
        );

        pearl = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearl.initialize, (address(7)));

        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearl), init);
        pearl = Pearl(address(pearlProxy));

        VotingEscrow votingEscrowImpl = new VotingEscrow(address(pearlProxy));
        voter = new Voter();

        init = abi.encodeCall(
            voter.initialize,
            (
                address(votingEscrowImpl),
                address(1),
                address(2),
                factoryProxyAddress
            )
        );
        ERC1967Proxy voterProxy = new ERC1967Proxy(address(voter), init);
        voter = Voter(address(voterProxy));

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);

        init = abi.encodeCall(
            votingEscrowImpl.initialize,
            (address(vesting), address(5), address(0))
        );

        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(
            address(votingEscrowImpl),
            init
        );

        address[] memory addr = new address[](1);
        addr[0] = address(pearl);

        voter.setVotingEscrow(address(votingEscrowProxy));
        voter._initialize(addr, address(8));

        bribeFactory = new BribeFactory();

        init = abi.encodeCall(BribeFactory.initialize, (address(voter), addr));

        ERC1967Proxy mainProxy = new ERC1967Proxy(address(bribeFactory), init);
        bribeFactory = BribeFactory(address(mainProxy));
    }

    function test_AssertInitialization() public {
        assertEq(bribeFactory.voter(), address(voter));
        assertEq(bribeFactory.hasRole(0x00, address(this)), true);

        assertEq(bribeFactory.defaultRewardToken(0), address(pearl));
        assertEq(bribeFactory.isDefaultRewardToken(address(pearl)), true);

        assertEq(
            bribeFactory.hasRole(keccak256("BRIBE_ADMIN"), address(this)),
            true
        );
    }

    //////////////////////////////////  ONLY OWNER INTERACTIONS //////////////////////////////////

    function test_BribeDeployment() public {
        address bribe = bribeFactory.createBribe(
            address(1),
            address(3),
            address(6),
            "_type"
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                BribeFactory_Zero_Address_Not_Allowed.selector
            )
        );

        bribeFactory.pushDefaultRewardToken(address(0));
    }

    function test_ShouldFailIfTokenAlreadyExist() public {
        address newToken = makeAddr("newToken");
        bribeFactory.pushDefaultRewardToken(newToken);

        vm.expectRevert(
            abi.encodeWithSelector(BribeFactory_Token_Already_Added.selector)
        );

        bribeFactory.pushDefaultRewardToken(newToken);
    }

    function test_ShouldFailIfTokenIsNotRewardToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BribeFactory_Not_A_Default_Reward_Token.selector
            )
        );
        bribeFactory.removeDefaultRewardToken(makeAddr("newToken"));
    }

    function test_ShouldFailIfTokenIsTheSame() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BribeFactory_Tokens_Cannot_Be_The_Same.selector
            )
        );

        bribeFactory.createBribe(address(1), address(3), address(3), "_type");
    }

    ////////////////////////////////// ONLY OWNER or BRIBE ADMIN INTERACTIONS //////////////////////////////////

    function test_ShouldAddRewardTokenToBrideContract() public {
        address bribe = bribeFactory.createBribe(
            makeAddr("owner"),
            address(0),
            address(0),
            "_type"
        );

        bribeFactory.addRewardToBribe(makeAddr("rewardToken"), bribe);
        assertEq(IBribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
    }

    function test_ShouldAddRewardTokensToBrideContract() public {
        address bribe = bribeFactory.createBribe(
            makeAddr("owner"),
            address(0),
            address(0),
            "_type"
        );

        address[] memory addr = new address[](2);
        addr[0] = makeAddr("rewardToken");

        addr[1] = makeAddr("rewardToken1");
        bribeFactory.addRewardsToBribe(addr, bribe);

        assertEq(IBribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(IBribe(bribe).rewardTokens(2), makeAddr("rewardToken1"));
    }

    function test_ShouldAddRewardTokenToBrideContracts() public {
        address bribe = bribeFactory.createBribe(
            makeAddr("owner"),
            address(0),
            address(0),
            "_type"
        );

        address bribe0 = bribeFactory.createBribe(
            makeAddr("owner"),
            address(0),
            address(0),
            "_type"
        );
        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        bribeFactory.addRewardToBribes(makeAddr("rewardToken"), bribes);

        assertEq(IBribe(bribes[0]).rewardTokens(1), makeAddr("rewardToken"));
        assertEq(IBribe(bribes[1]).rewardTokens(1), makeAddr("rewardToken"));
    }

    function test_ShouldAddRewardsTokenToBrideContracts() public {
        address bribe = bribeFactory.createBribe(
            makeAddr("owner"),
            address(0),
            address(0),
            "_type"
        );

        address bribe0 = bribeFactory.createBribe(
            makeAddr("owner"),
            address(0),
            address(0),
            "_type"
        );
        address[] memory bribes = new address[](2);
        bribes[0] = bribe;
        bribes[1] = bribe0;

        address[][] memory rewards = new address[][](2);
        // rewards[1][1] = makeAddr("rewardToken");
        // rewards[0][1] = makeAddr("rewardToken0");

        // bribeFactory.addRewardsToBribes(rewards, bribes);
        console.log(rewards.length);
    }

    // function test_ShouldSetBribeVoter() public {
    //     address bribe = bribeFactory.createBribe(
    //         makeAddr("owner"),
    //         address(0),
    //         address(0),
    //         "_type"
    //     );

    //     address bribe0 = bribeFactory.createBribe(
    //         makeAddr("owner"),
    //         address(0),
    //         address(0),
    //         "_type"
    //     );
    //     address[] memory bribes = new address[](2);
    //     bribes[0] = bribe;
    //     bribes[1] = bribe0;

    //     makeAddr("voter");
    //     bribeFactory.setBribeVoter(bribes, makeAddr("voter"));

    //     //     assertEq(IBribe(bribe).rewardTokens(1), makeAddr("rewardToken"));
    //     //     assertEq(IBribe(bribe).rewardTokens(2), makeAddr("rewardToken1"));
    // }
}
