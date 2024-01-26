// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IPearl} from "../src/interfaces/IPearl.sol";
import {console2 as console} from "forge-std/Test.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";
import {RewardsDistributor} from "../src/v1.5/RewardsDistributor.sol";

interface IERC20EXTT {
    function balanceOf(address from) external returns (uint);
}

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;
    AddressSet internal _actors;

    IPearl public pearl;
    IVotingEscrow public ve;
    RewardsDistributor public rewardsDistributor;

    mapping(address => uint) ids;
    mapping(bytes32 => uint256) public calls;

    address currentActor;
    uint256 public ghost_zeroMint;
    uint256 public ghost_mintedSum;
    uint256 public ghost_actualMint;

    constructor(
        RewardsDistributor _rewardsDistributor,
        address _ve,
        address _pearl
    ) {
        pearl = IPearl(_pearl);
        ve = IVotingEscrow(_ve);
        rewardsDistributor = _rewardsDistributor;
    }

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(currentActor);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function mintNFT(
        uint256 amount,
        uint256 duration
    ) public createActor countCall("mint") {
        if (ids[currentActor] == 0) {
            ghost_actualMint++;
            amount = bound(amount, 0, type(uint8).max);
            duration = bound(amount, 2 weeks, 2 * 52 weeks);

            if (amount != 0) {
                ghost_actualMint++;
                ghost_mintedSum += amount;

                __mint(currentActor, amount);
                vm.startPrank(currentActor);
                pearl.approve(address(ve), amount);

                (bool success0, bytes memory data) = address(ve).call(
                    abi.encodeWithSignature(
                        "mint(address,uint256,uint256)",
                        currentActor,
                        amount,
                        duration
                    )
                );

                assert(success0);
                uint256 id = abi.decode(data, (uint256));

                ids[currentActor] = id;
                vm.stopPrank();
            } else ghost_zeroMint++;
        }
    }

    function setRewardAmount(uint256 amount) public countCall("set reward") {
        amount = bound(amount, 0, 1000000000000000);

        if (amount != 0) {
            vm.startPrank(address(11));

            vm.warp(block.timestamp + 7 hours);

            if (
                rewardsDistributor._currentEpochTimestamp() >
                rewardsDistributor.lastRewardEpochTimestamp()
            ) {
                rewardsDistributor.notifyRewardAmount(amount);
            } else {}

            vm.stopPrank();
        } else {}
    }

    function claim(
        uint256 actorSeed
    ) public useActor(actorSeed) countCall("claim") {
        address claimer = _actors.rand(actorSeed);
        uint256 tokenId = ids[claimer];
        if (rewardsDistributor.claimable(tokenId) != 0) {
            if (
                rewardsDistributor.claimable(tokenId) <=
                pearl.balanceOf(address(this))
            ) {
                rewardsDistributor.claim(tokenId);
            }
        }
    }

    function reduceActors(
        uint256 acc,
        function(uint256, address) external returns (uint256) func
    ) public returns (uint256) {
        return _actors.reduce(acc, func);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function callSummary() external view {
        console.log("-------------------");
        console.log("  ");
        console.log("Call summary:");
        console.log("  ");
        console.log("-------------------");
        console.log("Call Count:");
        console.log("-------------------");
        console.log("Mint(s)", calls["mint"]);
        console.log("Claim(s)", calls["claim"]);
        console.log("Set Reward(s)", calls["set reward"]);
        console.log("-------------------");
        console.log("Zero Calls:");
        console.log("-------------------");
        console.log("Mint(s):", ghost_zeroMint);
        console.log("-------------------");
        console.log("-------------------");
        console.log("Actual Calls:");
        console.log("-------------------");
        console.log("Mint(s):", ghost_actualMint);
    }

    function __mint(address addr, uint256 amount) internal {
        vm.startPrank(address(11));
        (bool success, ) = address(pearl).call(
            abi.encodeWithSignature("mint(address,uint256)", addr, amount)
        );
        assert(success);
        vm.stopPrank();
    }
}
