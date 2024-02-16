// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RewardsDistributor} from "../src/v1.5/RewardsDistributor.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Uint Test For Rewards Distributor Contract
 * @author c-n-o-t-e
 * @dev Contract is used to test out Rewards Distributor Contract-
 *      by forking the UNREAL chain to interact with voting escrow contract.
 *
 * Functionalities Tested:
 * - Failed scenario initializing the contract.
 * - Failed scenario setting the owner address.
 * - Failed scenario setting amount for reward.
 * - Failed scenario setting the depositor address.
 * - Failed scenario when withdrawing ERC20 from contract.
 * - Failed scenario when caller of the claim() has no reward to claim.
 * - Successfully set the owner address.
 * - Successfully initialize the contract.
 * - Successfully set the depositor address.
 * - Successfully claim rewards from claim().
 * - Successfully check claimable amounts for token IDs.
 * - Successfully withdraw ERC20 tokens from the contract.
 * - Successfully increase locked user tokens when vesting duration is above zero.
 * - Successfully claiming rewards for a given token ID based on its voting power.
 */

contract RewardsDistributorTest is Test {
    error NoClaimableAmount();

    using SafeERC20 for IERC20;

    RewardsDistributor public rewardsDistributor;

    address pearlHolder = 0x95e3664633A8650CaCD2c80A0F04fb56F65DF300;
    address VotingEscrowVesting = 0xA1Bc24d9043C364bF9BAc192ef9a46B8d8f24dCD;

    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    address votingEscrow = 0xee60171b3A81EE2DF0caf0aAd894772B6Acaa772;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 11000);
        RewardsDistributor main = new RewardsDistributor();

        ERC1967Proxy mainProxy = new ERC1967Proxy(
            address(main), abi.encodeWithSelector(RewardsDistributor.initialize.selector, votingEscrow)
        );

        rewardsDistributor = RewardsDistributor(address(mainProxy));
        rewardsDistributor.setDepositor(address(8));

        vm.startPrank(pearlHolder);
        IERC20(rewardsDistributor.token()).safeTransfer(address(6), 10 ether);
        vm.stopPrank();
    }

    function test_initialize() public {
        RewardsDistributor main = new RewardsDistributor();
        assertEq(main.owner(), address(0));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(main), abi.encodeWithSelector(RewardsDistributor.initialize.selector, votingEscrow)
        );

        rewardsDistributor = RewardsDistributor(address(proxy));
        assertEq(rewardsDistributor.owner(), address(this));
    }

    function test_should_set_depositor_address() public {
        rewardsDistributor.setDepositor(address(8));
        assertEq(rewardsDistributor.depositor(), address(8));
    }

    function test_should_set_owner_address() public {
        rewardsDistributor.setOwner(address(8));
        assertEq(rewardsDistributor.owner(), address(8));
    }

    function test_should_notify_reward_amount() public {
        rewardsDistributor.setDepositor(address(8));
        vm.startPrank(address(8));
        rewardsDistributor.notifyRewardAmount(20000);
    }

    function test_should_fail_when_reward_for_current_is_already_set() public {
        rewardsDistributor.setDepositor(address(8));
        vm.startPrank(address(8));
        rewardsDistributor.notifyRewardAmount(20000);

        vm.expectRevert("RewardsDistributor: reward for current epoch already set");

        rewardsDistributor.notifyRewardAmount(20000);
    }

    function test_should_return_zero_when_user_have_not_minted() public {
        uint256 rewardToClaim = rewardsDistributor.claimable(100);
        assertEq(rewardToClaim, 0);
    }

    function test_should_return_an_amount_to_claim_when_user_have_minted() public {
        uint256 nftID = __mint();
        vm.startPrank(address(8));
        // user can't claim rewards in same epoch they mint

        vm.warp(block.timestamp + 7 days);
        rewardsDistributor.notifyRewardAmount(20000 ether);
        // user can't claim rewards for the current epoch

        vm.warp(block.timestamp + 7 days);
        rewardsDistributor.notifyRewardAmount(20000 ether);
        // user can only claim rewards for pass epoch and only when lastRewardEpochTimestamp is above user lastClaimEpochTimestamp

        uint256 rewardToClaim = rewardsDistributor.claimable(nftID);
        assertGt(rewardToClaim, 0);
    }

    function test_should_fail_when_caller_has_no_reward_to_claim() public {
        vm.expectRevert(abi.encodeWithSelector(NoClaimableAmount.selector));
        rewardsDistributor.claim(100);
    }

    function test_should_increase_locked_user_tokens() public {
        uint256 nftID = __mint();
        vm.warp(block.timestamp + 7 days);

        vm.startPrank(address(8));
        rewardsDistributor.notifyRewardAmount(20000 ether);

        vm.warp(block.timestamp + 7 days);
        rewardsDistributor.notifyRewardAmount(20000 ether);

        (bool success0, bytes memory data0) =
            votingEscrow.staticcall(abi.encodeWithSignature("getLockedAmount(uint256)", nftID));

        assert(success0);
        uint256 rewardToClaim = rewardsDistributor.claim(nftID);
        assertGt(rewardToClaim, 0);

        (bool success00, bytes memory data00) =
            votingEscrow.staticcall(abi.encodeWithSignature("getLockedAmount(uint256)", nftID));

        console.log(IERC20(rewardsDistributor.token()).balanceOf(address(rewardsDistributor)));

        assert(success00);
        assertGt(abi.decode(data00, (uint256)), abi.decode(data0, (uint256)));
    }

    function test_should_fail_when_amount_to_withdraw_is_zero() public {
        address token = rewardsDistributor.token();
        vm.expectRevert("RewardsDistributor: no withdrawable amount");
        rewardsDistributor.withdrawERC20(token);
    }

    function test_should_withdraw_available_funds_and_leave_reserve() public {
        address owner = rewardsDistributor.owner();
        IERC20 token = IERC20(rewardsDistributor.token());

        vm.startPrank(address(8));
        // 2000 ether is added to token reserve
        rewardsDistributor.notifyRewardAmount(2000 ether);

        vm.startPrank(pearlHolder);
        // 10000 ether is added to contract balance directly
        token.safeTransfer(address(rewardsDistributor), 10000 ether);
        vm.stopPrank();

        vm.startPrank(owner);

        uint256 contractBalanceBeforeTx = token.balanceOf(address(rewardsDistributor));

        assertEq(contractBalanceBeforeTx, 10000 ether);
        uint256 ownerBalanceBeforeTx = token.balanceOf(owner);

        assertEq(ownerBalanceBeforeTx, 0);
        rewardsDistributor.withdrawERC20(address(token));

        uint256 contractBalanceAfterTx = token.balanceOf(address(rewardsDistributor));

        assertEq(contractBalanceAfterTx, 2000 ether);
        uint256 ownerBalanceAfterTx = token.balanceOf(owner);
        assertEq(ownerBalanceAfterTx, 8000 ether);
    }

    function test_should_let_user_claim_reward_when_an_NFT_is_Fully_Vested() public {
        uint256 nftID = __mint();
        IERC20 token = IERC20(rewardsDistributor.token());

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 7 days);
            vm.startPrank(address(8));
            rewardsDistributor.notifyRewardAmount(2000 ether);
        }

        vm.startPrank(VotingEscrowVesting);
        (bool success,) = votingEscrow.call(abi.encodeWithSignature("updateVestingDuration(uint256,uint256)", nftID, 0));
        assert(success);

        (bool success0, bytes memory data0) =
            votingEscrow.staticcall(abi.encodeWithSignature("ownerOf(uint256)", nftID));

        assert(success0);
        assertEq(abi.decode(data0, (address)), address(6));

        assertGt(rewardsDistributor.claimable(nftID), 0);
        assertEq(token.balanceOf(address(6)), 0);

        rewardsDistributor.claim(nftID);
        assertEq(rewardsDistributor.claimable(nftID), 0);
        assertGt(token.balanceOf(address(6)), 0);
    }

    function test_should_claim_twice_if_rewards_to_claim_is_above_50_epochs() public {
        uint256 nftID = __mint();
        vm.startPrank(address(8));
        IERC20 token = IERC20(rewardsDistributor.token());

        for (uint256 i = 0; i < 52; i++) {
            vm.warp(block.timestamp + 7 days);
            rewardsDistributor.notifyRewardAmount(2000 ether);
        }

        vm.startPrank(VotingEscrowVesting);
        (bool success,) = votingEscrow.call(abi.encodeWithSignature("updateVestingDuration(uint256,uint256)", nftID, 0));

        assert(success);

        (bool success0, bytes memory data0) =
            votingEscrow.staticcall(abi.encodeWithSignature("ownerOf(uint256)", nftID));

        assert(success0);
        assertEq(abi.decode(data0, (address)), address(6));

        // user claims rewards up to 50 count limit
        rewardsDistributor.claim(nftID);
        uint256 firstRewardClaimedAfterTx = token.balanceOf(address(6));

        // user claim remaining rewards
        rewardsDistributor.claim(nftID);

        uint256 secondRewardClaimedAfterTx = token.balanceOf(address(6));
        assertGt(secondRewardClaimedAfterTx, firstRewardClaimedAfterTx);
    }

    function __mint() internal returns (uint256 nftID) {
        vm.startPrank(pearlHolder);
        IERC20(rewardsDistributor.token()).safeTransfer(address(rewardsDistributor), 10000 ether);
        vm.stopPrank();

        vm.startPrank(address(6));

        IERC20(rewardsDistributor.token()).safeIncreaseAllowance(address(votingEscrow), 10 ether);

        (bool success, bytes memory data) =
            votingEscrow.call(abi.encodeWithSignature("mint(address,uint256,uint256)", address(6), 10 ether, 3 weeks));

        assert(success);
        nftID = abi.decode(data, (uint256));
    }
}
