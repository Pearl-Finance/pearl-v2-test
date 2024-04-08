// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Voter} from "../../src/Voter.sol";
import {GaugeV2} from "../../src/GaugeV2.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Bribe} from "../../src/v1.5/Bribe.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OFTMockToken} from ".././OFTMockToken.sol";
import {TestERC20} from "../../src/mock/TestERC20.sol";
import {console2 as console} from "forge-std/Test.sol";
import {IMinter} from "../../src/interfaces/IMinter.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";
import {IVotingEscrow} from "../../src/interfaces/IVotingEscrow.sol";
import {IVotingEscrow} from "../../src/interfaces/IVotingEscrow.sol";
import {IEpochController} from "../../src/interfaces/IEpochController.sol";
import {IPearlV2Factory} from "../../src/interfaces/dex/IPearlV2Factory.sol";
import {MathUpgradeable} from "openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    AddressSet internal _actors;

    TestERC20 public testERC20;
    TestERC20 public tokenX;
    OFTMockToken public nativeOFT;
    address public ve;
    Voter public voter;
    Bribe public bribe;
    GaugeV2 public gauge;
    IMinter public minter;
    IEpochController public epochController;
    address pool;
    address[] pools;

    mapping(address => uint256) ids;
    mapping(address => bool) hasVoted;
    mapping(bytes32 => uint256) public calls;
    mapping(address => uint256) public ghost_usersVotes;
    mapping(address => uint256) public ghost_gaugesRewards;

    address tester;
    address currentActor;
    address lzEndPointMockL1;

    uint256 public ghost_zeroMint;
    uint256 public ghost_mintedSum;
    uint256 public ghost_actualMint;
    uint256 public ghost_usersVote;
    uint256 public ghost_rebaseRewards;
    uint256 public ghost_teamEmissions;
    uint256 public ghost_totalGaugesRewards;
    uint256 weekly = 2_600_000 * 10 ** 18;
    uint256 public emission = 990;
    uint256 public teamRate = 25;
    uint256 public constant PRECISION = 1_000;
    uint256 rebaseMax = 5_00;
    uint256 rebaseSlope = 625;

    constructor(
        Voter _voter,
        address _ve,
        address _testERC20,
        address _pool,
        GaugeV2 _gauge,
        address _epochController,
        address _lzEndPointMockL1,
        address _tester,
        address[] memory _pools
    ) {
        testERC20 = TestERC20(_testERC20);
        ve = _ve;
        voter = _voter;
        pool = _pool;
        gauge = _gauge;
        epochController = IEpochController(_epochController);
        bribe = Bribe(voter.external_bribes(address(gauge)));
        minter = IMinter(voter.minter());
        lzEndPointMockL1 = _lzEndPointMockL1;
        tester = _tester;
        pools = _pools;
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

    function mintNFT(uint256 amount, uint256 duration) public createActor countCall("mint") {
        if (ids[currentActor] == 0) {
            ghost_actualMint++;
            amount = bound(amount, 0, type(uint8).max);

            duration = bound(amount, 2 weeks, 2 * 52 weeks);

            if (amount != 0 && !IEpochController(epochController).checkDistribution()) {
                if (amount < 1e18) amount = amount * 1e18;
                ghost_actualMint++;
                ghost_mintedSum += amount;

                __mint(currentActor, amount);
                vm.startPrank(currentActor);
                testERC20.approve(address(ve), amount);

                (bool success0, bytes memory data) = address(ve).call(
                    abi.encodeWithSignature("mint(address,uint256,uint256)", currentActor, amount, duration)
                );

                assert(success0);
                uint256 id = abi.decode(data, (uint256));

                ids[currentActor] = id;
                vm.stopPrank();
            } else {
                ghost_zeroMint++;
            }
        }
    }

    function vote(uint256 actorSeed, uint256 weight, uint256 poolID)
        public
        useActor(actorSeed)
        countCall("set reward")
    {
        weight = 1;
        poolID = bound(poolID, 0, pools.length - 1);

        if (weight > 0) {
            address[] memory _poolVote = new address[](1);
            _poolVote[0] = pools[poolID];

            uint256[] memory _weights = new uint256[](1);
            _weights[0] = weight;

            address gauge_ = voter.gauges(pools[poolID]);
            Bribe b = Bribe(voter.external_bribes(address(gauge_)));

            uint256 vote = IVotingEscrow(ve).getVotes(currentActor);
            uint256 previousBalance = b.balanceOf(currentActor);

            if (vote > 0) {
                vm.startPrank(currentActor);
                voter.vote(_poolVote, _weights);
                vm.stopPrank();

                if (hasVoted[currentActor]) {
                    userVotes(currentActor, previousBalance, true, b, pools[poolID]);
                } else {
                    userVotes(currentActor, 0, false, b, pools[poolID]);
                }

                hasVoted[currentActor] = true;
            }
        }
    }

    bool firstTime;

    function distribute() public {
        if (ghost_usersVote > 0) {
            uint256 _weekly;

            if (!firstTime) {
                _weekly = weekly;
                firstTime = true;
            } else {
                weekly = weekly_emission();
                _weekly = weekly;
            }

            uint256 _rebase = calculate_rebase(_weekly);
            uint256 _teamEmissions = (_weekly * teamRate) / PRECISION;
            uint256 gaugesReward = _weekly - _rebase - _teamEmissions;

            uint256 _ratio = (gaugesReward * 1e18) / voter.totalWeight();
            uint256 index = voter.index();
            index += _ratio;
            gaugesReward = _updateFor(index);

            ghost_rebaseRewards += _rebase;
            ghost_teamEmissions += _teamEmissions;
            ghost_totalGaugesRewards += gaugesReward;

            vm.warp(block.timestamp + minter.nextPeriod());
            epochController.distribute();

            if (IEpochController(epochController).checkDistribution()) {
                // finish distribution
                while (IEpochController(epochController).checkDistribution()) {
                    epochController.distribute();
                }
            }
        }
    }

    function _updateFor(uint256 index) internal returns (uint256 _share) {
        for (uint256 i = 0; i < pools.length; i++) {
            address gauge_ = voter.gauges(pools[i]);
            uint256 _supplied = voter.weights(pools[i]);

            if (_supplied != 0) {
                uint256 _supplyIndex = voter.supplyIndex(address(gauge_));
                uint256 _delta = index - _supplyIndex;

                if (_delta != 0) {
                    uint256 reward = (_supplied * _delta) / 1e18;
                    _share += reward;
                    ghost_gaugesRewards[gauge_] += reward;
                }
            }
        }
    }

    function userVotes(address actor, uint256 previousBalance, bool voted, Bribe b, address votePool) internal {
        if (voted) {
            ghost_usersVote -= previousBalance;
            ghost_usersVote += b.balanceOf(actor);

            ghost_usersVotes[votePool] -= previousBalance;
            ghost_usersVotes[votePool] += b.balanceOf(actor);
        } else {
            ghost_usersVote += b.balanceOf(actor);
            ghost_usersVotes[votePool] += b.balanceOf(actor);
        }
    }

    function claim(uint256 actorSeed) public useActor(actorSeed) countCall("claim") {}

    function reduceActors(uint256 acc, function(uint256, address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
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
        (bool success,) = address(testERC20).call(abi.encodeWithSignature("mint(address,uint256)", addr, amount));
        assert(success);
        vm.stopPrank();
    }

    function weekly_emission() public view returns (uint256) {
        uint256 calculate_emission = (weekly * emission) / PRECISION;
        uint256 circulating_supply = testERC20.totalSupply() - testERC20.balanceOf(ve);
        circulating_supply = (circulating_supply * 2) / PRECISION;
        return MathUpgradeable.max(circulating_supply, calculate_emission);
    }

    function calculate_rebase(uint256 _weeklyMint) public view returns (uint256) {
        uint256 _veTotal = testERC20.balanceOf(address(ve));
        uint256 _pearlTotal = testERC20.totalSupply();

        uint256 lockedShare = (_veTotal * rebaseSlope) / _pearlTotal;
        if (lockedShare >= rebaseMax) {
            lockedShare = rebaseMax;
        }

        return (_weeklyMint * lockedShare) / PRECISION;
    }
}
