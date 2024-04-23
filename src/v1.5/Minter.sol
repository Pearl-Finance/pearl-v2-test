// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20, SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IMinter.sol";
import "../interfaces/IRewardsDistributor.sol";
import "../interfaces/IPearl.sol";
import "../interfaces/IVoter.sol";
import "../interfaces/IVotingEscrow.sol";
import "../Epoch.sol";
import {console2 as console} from "forge-std/Test.sol";

// codifies the minting rules as per ve(3,3), abstracted from the token to support any token that allows minting
contract Minter is IMinter, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant TAIL_EMISSION = 2;
    uint256 public constant PRECISION = 1_000;
    uint256 public constant MAX_TEAM_RATE = 5_0; // 5%
    uint256 public constant LOCK = EPOCH_DURATION * 52 * 2; // 2 years

    bool public isFirstMint;

    uint256 public emission;

    uint256 public rebaseMax;
    uint256 public rebaseSlope;
    uint256 public teamRate;

    uint256 public weekly;
    uint256 public active_period;

    address internal _initializer;
    address public team;
    address public pendingTeam;

    IPearl public _pearl;
    IVoter public _voter;
    IVotingEscrow public _ve;
    IRewardsDistributor public override _rewards_distributor;

    bool private _paused;

    event Mint(address indexed sender, uint256 weekly, uint256 circulating_supply, uint256 circulating_emission);

    event Paused(bool indexed isPaused);

    event VoterChanged(address indexed voter);

    event TeamChanged(address indexed team);

    event TeamRateChanged(uint256 indexed teamRate);

    event RebaseChanged(uint256 indexed max, uint256 slope);

    event EmissionChanged(uint256 indexed emission);

    event TeamChangedAccepted(address indexed pendingTeam);

    event RewardDistributorSet(address indexed rewardDistro);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _intialOwner,
        address __voter, // the voting & distribution system
        address __ve, // the ve(3,3) system that will be locked into
        address __rewards_distributor // the distribution system that ensures users aren't diluted
    ) public initializer {
        require(
            _intialOwner != address(0) && __voter != address(0) && __ve != address(0)
                && __rewards_distributor != address(0),
            "!zero address"
        );

        __Ownable_init();
        _transferOwnership(_intialOwner);

        team = _intialOwner;

        teamRate = 25;

        emission = 990;
        rebaseMax = 5_00;
        rebaseSlope = 625;

        _pearl = IPearl(address(IVotingEscrow(__ve).lockedToken()));
        _voter = IVoter(__voter);
        _ve = IVotingEscrow(__ve);
        _rewards_distributor = IRewardsDistributor(__rewards_distributor);

        active_period = (block.timestamp / EPOCH_DURATION) * EPOCH_DURATION + EPOCH_DURATION; // active_period is set to start at the beginning of the next day from deployment.

        weekly = 2_600_000 * 10 ** 18; // represents a starting weekly emission of 2.6M PEARL
        isFirstMint = true;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function setTeam(address _team) external {
        require(msg.sender == team, "not team");
        pendingTeam = _team;
        emit TeamChanged(_team);
    }

    function acceptTeam() external {
        address _pendingTeam = pendingTeam;
        require(msg.sender == _pendingTeam, "not pending team");
        team = _pendingTeam;
        emit TeamChangedAccepted(_pendingTeam);
    }

    function setVoter(address __voter) external {
        require(__voter != address(0));
        require(msg.sender == team, "not team");
        _voter = IVoter(__voter);
        emit VoterChanged(__voter);
    }

    function setTeamRate(uint256 _teamRate) external {
        require(msg.sender == team, "not team");
        require(_teamRate <= MAX_TEAM_RATE, "rate too high");
        teamRate = _teamRate;
        emit TeamRateChanged(_teamRate);
    }

    function setEmission(uint256 _emission) external {
        require(msg.sender == team, "not team");
        require(_emission <= PRECISION, "rate too high");
        emission = _emission;
        emit EmissionChanged(_emission);
    }

    function setRebase(uint256 _max, uint256 _slope) external {
        require(msg.sender == team, "not team");
        require(_max <= PRECISION, "rate too high");
        rebaseMax = _max;
        rebaseSlope = _slope;
        emit RebaseChanged(_max, _slope);
    }

    // calculate circulating supply as total token supply - locked supply
    function circulating_supply() public view returns (uint256 _circulating) {
        unchecked {
            _circulating = _pearl.totalSupply() - _pearl.balanceOf(address(_ve));
        }
    }

    // emission calculation is 1% of available supply to mint adjusted by circulating / total supply
    function calculate_emission() public view returns (uint256) {
        return (weekly * emission) / PRECISION;
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weekly_emission() public view returns (uint256) {
        return MathUpgradeable.max(calculate_emission(), circulating_emission());
    }

    // calculates tail end (infinity) emissions as 0.2% of total supply
    function circulating_emission() public view returns (uint256) {
        return (circulating_supply() * TAIL_EMISSION) / PRECISION;
    }

    // calculate the rebase protection rate, which is to protect against inflation
    function calculate_rebase(uint256 _weeklyMint) public view returns (uint256) {
        uint256 _veTotal = _pearl.balanceOf(address(_ve));
        uint256 _pearlTotal = _pearl.totalSupply();

        uint256 lockedShare = (_veTotal * rebaseSlope) / _pearlTotal;
        if (lockedShare >= rebaseMax) {
            lockedShare = rebaseMax;
        }

        return (_weeklyMint * lockedShare) / PRECISION;
    }

    // update period can only be called once per cycle (1 week)
    function update_period() external returns (uint256) {
        uint256 _period = active_period;

        if (block.timestamp >= _period + EPOCH_DURATION && _initializer == address(0)) {
            // only trigger if new week
            _period = (block.timestamp / EPOCH_DURATION) * EPOCH_DURATION;
            active_period = _period;

            if (paused()) {
                _rewards_distributor.notifyRewardAmount(0);
                _voter.notifyRewardAmount(0);
                emit Mint(msg.sender, 0, circulating_supply(), circulating_emission());
            } else {
                if (!isFirstMint) {
                    weekly = weekly_emission();
                } else {
                    isFirstMint = false;
                }

                uint256 _weekly = weekly;
                uint256 _rebase = calculate_rebase(_weekly);
                uint256 _teamEmissions = (_weekly * teamRate) / PRECISION;
                uint256 _required = _weekly;
                IPearl pearl = _pearl;

                uint256 _gauge = _weekly - _rebase - _teamEmissions;

                uint256 _balanceOf = pearl.balanceOf(address(this));
                if (_balanceOf < _required) {
                    unchecked {
                        pearl.mint(address(this), _required - _balanceOf);
                    }
                }

                IERC20(address(pearl)).safeTransfer(team, _teamEmissions);
                IERC20(address(pearl)).safeTransfer(address(_rewards_distributor), _rebase);
                _rewards_distributor.notifyRewardAmount(_rebase);
                IERC20(address(pearl)).forceApprove(address(_voter), _gauge);
                _voter.notifyRewardAmount(_gauge);

                emit Mint(msg.sender, _weekly, circulating_supply(), circulating_emission());
            }
        }
        return _period;
    }

    function check() external view returns (bool) {
        uint256 _period = active_period;
        return (block.timestamp >= _period + EPOCH_DURATION && _initializer == address(0));
    }

    function period() external view returns (uint256) {
        return (block.timestamp / EPOCH_DURATION) * EPOCH_DURATION;
    }

    function nextPeriod() external view returns (uint256) {
        return active_period + EPOCH_DURATION;
    }

    function setRewardDistributor(address _rewardDistro) external {
        require(msg.sender == team, "!team");
        require(_rewardDistro != address(0), "zero addr");
        _rewards_distributor = IRewardsDistributor(_rewardDistro);
        emit RewardDistributorSet(_rewardDistro);
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function pause() external whenNotPaused onlyOwner {
        _paused = true;
        emit Paused(true);
    }

    function unpause() external whenPaused onlyOwner {
        _paused = false;
        emit Paused(false);
    }

    function _requireNotPaused() internal view virtual {
        require(!_paused, "Pausable: paused");
    }

    function _requirePaused() internal view virtual {
        require(_paused, "Pausable: not paused");
    }
}
