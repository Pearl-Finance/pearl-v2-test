// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Handler} from "./Handler.sol";
import {Pearl} from "pearl-token/src/token/Pearl.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {MockVoter} from "pearl-token/test/mocks/MockVoter.sol";
import {VotingMath} from "pearl-token/src/governance/VotingMath.sol";
import {RewardsDistributor} from "../src/v1.5/RewardsDistributor.sol";
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";

contract RewardsDistributorInvariants is Test {
    RewardsDistributor public rewardsDistributor;

    Pearl pearl;
    VotingEscrow vePearl;
    MockVoter public voter;
    Handler public handler;
    VotingEscrowVesting vesting;

    function setUp() public {
        voter = new MockVoter();

        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        Pearl pearlImpl = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearlImpl.initialize, (votingEscrowProxyAddress));
        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearlImpl), init);

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);

        VotingEscrow votingEscrowImpl = new VotingEscrow(address(pearlProxy));

        init = abi.encodeCall(votingEscrowImpl.initialize, (address(vesting), address(voter), address(0)));

        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrowImpl), init);

        pearl = Pearl(address(pearlProxy));
        pearl.setMinter(address(11));
        vePearl = VotingEscrow(address(votingEscrowProxy));

        rewardsDistributor = new RewardsDistributor();

        ERC1967Proxy mainProxy = new ERC1967Proxy(
            address(rewardsDistributor),
            abi.encodeWithSelector(RewardsDistributor.initialize.selector, address(vePearl))
        );

        rewardsDistributor = RewardsDistributor(address(mainProxy));
        rewardsDistributor.setDepositor(address(11));
        vm.startPrank(address(11));
        pearl.mint(address(rewardsDistributor), 100000 ether);
        vm.stopPrank();

        handler = new Handler(rewardsDistributor, address(vePearl), address(pearl));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.mintNFT.selector;
        selectors[1] = Handler.setRewardAmount.selector;
        selectors[2] = Handler.claim.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_mints() public {}

    function invariant_claims() public {}
}
