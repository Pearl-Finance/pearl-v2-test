// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {VotesUpgradeable} from "openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {ERC721Upgradeable} from "openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC721, IERC721Metadata} from "openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IVotes} from "openzeppelin/contracts/governance/utils/IVotes.sol";

import "./interfaces/IBribe.sol";
import "./interfaces/IBribeFactory.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IGaugeV2.sol";
import "./interfaces/IGaugeV2Factory.sol";
import "./interfaces/dex/IPearlV2Pool.sol";
import "./interfaces/dex/IPearlV2Factory.sol";
import "./Epoch.sol";

contract Voter is IVoter, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public _ve; // the ve token that governs these contracts
    address public factory; // the PairFactory
    address internal base;
    address public gaugefactory;
    address public bribefactory;
    address public lBoxFactory;
    address public minter;
    address public governor; // should be set to an IGovernor
    address public emergencyCouncil; // credibly neutral party similar to Curve's Emergency DAO

    uint256 internal index;
    mapping(address => uint256) internal supplyIndex;
    mapping(address => uint256) public claimable;

    uint256 public totalWeight; // total voting weight

    address[] public pools; // all pools viable for incentives
    mapping(address => address) public gauges; // pool => gauge
    mapping(address => address) public gaugesALM; // pool => alm
    mapping(address => uint256) public gaugesDistributionTimestamp;
    mapping(address => address) public poolForGauge; // gauge => pool
    mapping(address => address) public internal_bribes; // gauge => internal bribe (only fees)
    mapping(address => address) public external_bribes; // gauge => external bribe (real bribes)
    mapping(address => uint256) public weights; // pool => weight
    mapping(address => mapping(address => uint256)) public votes; // account => pool => votes
    mapping(address => address[]) public poolVote; // account => pools
    mapping(address => uint256) public usedWeights; // account => total voting weight of user
    mapping(address => uint256) public lastVoted; // account => timestamp of last vote, to ensure one vote per epoch
    mapping(address => bool) public isGauge;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isAlive;
    mapping(address => bool) public voted;

    address public ustb;

    mapping(address => bool) public isBribe;

    event GaugeCreated(
        address indexed gauge,
        address creator,
        address internal_bribe,
        address indexed external_bribe,
        address indexed pool
    );
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint256 weight);
    event Abstained(address indexed voter, uint256 weight);
    event Deposit(
        address indexed lp,
        address indexed gauge,
        uint256 tokenId,
        uint256 amount
    );
    event Withdraw(
        address indexed lp,
        address indexed gauge,
        uint256 tokenId,
        uint256 amount
    );
    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint256 amount
    );
    event DistributeReward(
        address indexed sender,
        address indexed gauge,
        uint256 amount
    );
    event Whitelisted(address indexed whitelister, address indexed token);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address __ve,
        address _factory,
        address _gauges,
        address _bribes
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _ve = __ve;
        factory = _factory;
        base = address(IVotingEscrow(__ve).lockedToken());
        gaugefactory = _gauges;
        bribefactory = _bribes;
        governor = msg.sender;
        emergencyCouncil = msg.sender;
    }

    function _initialize(address[] memory _tokens, address _minter) external {
        require(msg.sender == minter || msg.sender == emergencyCouncil);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _whitelist(_tokens[i]);
        }
        minter = _minter;
    }

    function reinitialize() external reinitializer(2) {
        // first distribution had the wrong period, fix it here
        uint256 currentTimestamp = IMinter(minter).active_period();
        for (uint256 i = pools.length; i != 0; ) {
            unchecked {
                --i;
            }
            address gauge = gauges[pools[i]];
            gaugesDistributionTimestamp[gauge] = currentTimestamp;
        }
    }

    function setMinter(address _minter) external {
        require(msg.sender == emergencyCouncil);
        minter = _minter;
    }

    function setGovernor(address _governor) public onlyOwner {
        governor = _governor;
    }

    function setEmergencyCouncil(address _council) public {
        require(msg.sender == emergencyCouncil);
        emergencyCouncil = _council;
    }

    function setUSTB(address _ustb) external {
        require(msg.sender == governor);
        ustb = _ustb;
    }

    function getIncentivizedPools() external view returns (address[] memory) {
        return pools;
    }

    function reset() external nonReentrant {
        address account = msg.sender;
        lastVoted[account] = block.timestamp;
        _reset(account);
        voted[account] = false;
    }

    function _reset(address account) internal {
        address[] storage _poolVote = poolVote[account];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[account][_pool];

            if (_votes != 0) {
                weights[_pool] -= _votes;
                votes[account][_pool] -= _votes;
                if (_votes > 0) {
                    IBribe(internal_bribes[gauges[_pool]])._withdraw(
                        uint256(_votes),
                        account
                    );
                    IBribe(external_bribes[gauges[_pool]])._withdraw(
                        uint256(_votes),
                        account
                    );
                    _totalWeight += _votes;
                } else {
                    _totalWeight -= _votes;
                }
                emit Abstained(account, _votes);
            }
        }
        totalWeight -= _totalWeight;
        usedWeights[account] = 0;
        delete poolVote[account];
    }

    function poke() external nonReentrant {
        _poke(msg.sender);
    }

    function poke(address account) external nonReentrant {
        require(msg.sender == _ve, "!ve");
        uint256 lastVotedEpoch = (lastVoted[account] / EPOCH_DURATION) *
            EPOCH_DURATION;
        uint256 currentEpoch = IMinter(minter).active_period();
        if (lastVotedEpoch < currentEpoch) return;
        _poke(account);
    }

    function _poke(address account) internal {
        address[] memory _poolVote = poolVote[account];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);
        for (uint256 i = _poolCnt; i != 0; ) {
            unchecked {
                --i;
            }
            _weights[i] = votes[account][_poolVote[i]];
        }
        _vote(account, _poolVote, _weights);
    }

    function _vote(
        address account,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        _reset(account);
        uint256 _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(_ve).getVotes(account);
        uint256 _totalVoteWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = _poolCnt; i != 0; ) {
            unchecked {
                --i;
            }
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = _poolCnt; i != 0; ) {
            unchecked {
                --i;
            }
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge]) {
                uint256 _poolWeight = (_weights[i] * _weight) /
                    _totalVoteWeight;
                require(votes[account][_pool] == 0);
                require(_poolWeight != 0);

                poolVote[account].push(_pool);

                weights[_pool] += _poolWeight;
                votes[account][_pool] += _poolWeight;

                IBribe(internal_bribes[_gauge])._deposit(
                    uint256(_poolWeight),
                    account
                );

                IBribe(external_bribes[_gauge])._deposit(
                    uint256(_poolWeight),
                    account
                );
                _usedWeight += _poolWeight;
                emit Voted(account, _poolWeight);
            }
        }
        if (_usedWeight != 0) voted[account] = true;
        totalWeight += _usedWeight;
        usedWeights[account] = _usedWeight;
    }

    function vote(
        address[] memory _poolVote,
        uint256[] memory _weights
    ) external nonReentrant {
        address account = msg.sender;
        require(_poolVote.length == _weights.length);
        lastVoted[account] = block.timestamp;
        _vote(account, _poolVote, _weights);
    }

    function whitelist(address _token) public {
        require(msg.sender == governor, "!governor");
        _whitelist(_token);
    }

    function _whitelist(address _token) internal {
        require(!isWhitelisted[_token], "already whitelisted");
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }

    function createGauge(address _pool) external returns (address) {
        require(gauges[_pool] == address(0x0), "exists");
        address[] memory allowedRewards = new address[](3);
        address[] memory internalRewards = new address[](2);
        bool isPair = IPearlV2Factory(factory).isPair(_pool);
        address tokenA;
        address tokenB;

        if (isPair) {
            // (tokenA, tokenB) = IPearlV2Pool(_pool).tokens();
            tokenA = IPearlV2Pool(_pool).token0();
            tokenB = IPearlV2Pool(_pool).token1();
            allowedRewards[0] = tokenA;
            allowedRewards[1] = tokenB;
            internalRewards[0] = tokenA;
            internalRewards[1] = tokenB;

            if (base != tokenA && base != tokenB) {
                allowedRewards[2] = base;
            }
        }

        if (msg.sender != governor) {
            // gov can create for any pool, even non-Pearl pairs
            require(isPair, "!_pool");
            require(
                isWhitelisted[tokenA] && isWhitelisted[tokenB],
                "!whitelisted"
            );
            require(
                ustb == address(0) || tokenA == ustb || tokenB == ustb,
                "!ustb"
            );
        }

        string memory _type = string.concat(
            "Pearl LP Fees: ",
            string(
                abi.encodePacked(
                    "aMM-",
                    IERC20MetadataUpgradeable(tokenA).symbol(),
                    "/",
                    IERC20MetadataUpgradeable(tokenB).symbol()
                )
            )
        );

        address _internal_bribe = IBribeFactory(bribefactory).createBribe(
            owner(),
            tokenA,
            tokenB,
            _type
        );
        isBribe[_internal_bribe] = true;

        _type = string.concat(
            "Pearl Bribes: ",
            string(
                abi.encodePacked(
                    "aMM-",
                    IERC20MetadataUpgradeable(tokenA).symbol(),
                    "/",
                    IERC20MetadataUpgradeable(tokenB).symbol()
                )
            )
        );

        address _external_bribe = IBribeFactory(bribefactory).createBribe(
            owner(),
            tokenA,
            tokenB,
            _type
        );
        isBribe[_external_bribe] = true;

        (address _gauge, address _almGauge) = IGaugeV2Factory(gaugefactory)
            .createGauge(
                factory,
                _pool,
                base, //rewardToken
                address(this), //Distribution
                _internal_bribe,
                isPair
            );

        IERC20Upgradeable(base).approve(_gauge, type(uint256).max);
        internal_bribes[_gauge] = _internal_bribe;
        external_bribes[_gauge] = _external_bribe;
        gauges[_pool] = _gauge;
        gaugesALM[_pool] = _almGauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        supplyIndex[_gauge] = index;
        pools.push(_pool);
        emit GaugeCreated(
            _gauge,
            msg.sender,
            _internal_bribe,
            _external_bribe,
            _pool
        );
        return _gauge;
    }

    function killGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        claimable[_gauge] = 0;
        emit GaugeKilled(_gauge);
    }

    function reviveGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(!isAlive[_gauge], "gauge already alive");
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    function emitDeposit(
        uint256 tokenId,
        address account,
        uint256 amount
    ) external {
        require(isGauge[msg.sender]);
        require(isAlive[msg.sender]);
        emit Deposit(account, msg.sender, tokenId, amount);
    }

    function emitWithdraw(
        uint256 tokenId,
        address account,
        uint256 amount
    ) external {
        require(isGauge[msg.sender]);
        emit Withdraw(account, msg.sender, tokenId, amount);
    }

    function length() external view returns (uint256) {
        return pools.length;
    }

    function poolVoteLength(address account) external view returns (uint256) {
        return poolVote[account].length;
    }

    function hasVoted(address _account) external view returns (bool) {
        return
            voted[_account] &&
            lastVoted[_account] >= IMinter(minter).active_period();
    }

    function notifyRewardAmount(uint256 amount) external {
        require(totalWeight != 0, "no votes");
        _safeTransferFrom(base, msg.sender, address(this), amount); // transfer the distro in
        uint256 _ratio = (amount * 1e18) / totalWeight; // 1e18 adjustment is removed during claim
        if (_ratio != 0) {
            index += _ratio;
        }
        emit NotifyReward(msg.sender, base, amount);
    }

    function _updateFor(address _gauge) internal {
        address _pool = poolForGauge[_gauge];
        uint256 _supplied = weights[_pool];
        if (_supplied != 0) {
            uint256 _supplyIndex = supplyIndex[_gauge];
            uint256 _index = index; // get global index0 for accumulated distro
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint256 _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta != 0) {
                uint256 _share = (_supplied * _delta) / 1e18; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens
    ) external {
        for (uint256 i = _bribes.length; i != 0; ) {
            unchecked {
                --i;
            }
            IBribe(_bribes[i]).getRewardForOwner(msg.sender, _tokens[i]);
        }
    }

    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens
    ) external {
        for (uint256 i = _fees.length; i != 0; ) {
            unchecked {
                --i;
            }
            IBribe(_fees[i]).getRewardForOwner(msg.sender, _tokens[i]);
        }
    }

    function distributeFees(address[] memory _gauges) external {
        for (uint256 i = _gauges.length; i != 0; ) {
            unchecked {
                --i;
            }
            if (IGaugeV2(_gauges[i]).isForPair()) {
                IGaugeV2(_gauges[i]).claimFees();
            }
        }
    }

    function distribute(address _gauge) public nonReentrant {
        IMinter(minter).update_period();
        uint256 lastTimestamp = gaugesDistributionTimestamp[_gauge];
        uint256 currentTimestamp = IMinter(minter).active_period();

        if (lastTimestamp < currentTimestamp) {
            _updateFor(_gauge);
            uint256 _claimable = claimable[_gauge];
            // distribute only if claimable is > 0, currentEpoch != lastepoch and gauge is alive
            if (_claimable != 0 && isAlive[_gauge]) {
                claimable[_gauge] = 0;
                gaugesDistributionTimestamp[_gauge] = currentTimestamp;
                IGaugeV2(_gauge).notifyRewardAmount(base, _claimable);
                emit DistributeReward(msg.sender, _gauge, _claimable);
            }
        }
    }

    function distributeAll() external {
        distribute(0, pools.length);
    }

    function distribute(uint256 start, uint256 finish) public {
        for (uint256 x = start; x < finish; ) {
            distribute(gauges[pools[x]]);
            unchecked {
                ++x;
            }
        }
    }

    function distribute(address[] memory _gauges) external {
        for (uint256 x = _gauges.length; x != 0; ) {
            unchecked {
                --x;
            }
            distribute(_gauges[x]);
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        if (value != 0) {
            require(token.code.length != 0);
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(
                    IERC20Upgradeable.transferFrom.selector,
                    from,
                    to,
                    value
                )
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))));
        }
    }

    function setBribeFactory(address _bribeFactory) external {
        require(msg.sender == emergencyCouncil);
        bribefactory = _bribeFactory;
    }

    function setGaugeFactory(address _gaugeFactory) external {
        require(msg.sender == emergencyCouncil);
        gaugefactory = _gaugeFactory;
    }

    function setPairFactory(address _factory) external {
        require(msg.sender == emergencyCouncil);
        factory = _factory;
    }

    function whitelist(address[] memory _token) public {
        require(msg.sender == governor);
        for (uint256 i = _token.length; i != 0; ) {
            unchecked {
                --i;
            }
            _whitelist(_token[i]);
        }
    }

    function initGauges(
        address[] memory _gauges,
        address[] memory _pools
    ) public {
        require(msg.sender == emergencyCouncil);
        for (uint256 i = _pools.length; i != 0; ) {
            unchecked {
                --i;
            }
            address _pool = _pools[i];
            address _gauge = _gauges[i];
            address tokenA;
            address tokenB;
            // (tokenA, tokenB) = IPearlV2Pool(_pool).tokens();

            tokenA = IPearlV2Pool(_pool).token0();
            tokenB = IPearlV2Pool(_pool).token1();

            string memory _poolStr = string(
                abi.encodePacked(
                    "aMM-",
                    IERC20MetadataUpgradeable(tokenA).symbol(),
                    "/",
                    IERC20MetadataUpgradeable(tokenB).symbol()
                )
            );

            string memory _type = string.concat("Pearl LP Fees: ", _poolStr);
            address _internal_bribe = IBribeFactory(bribefactory).createBribe(
                owner(),
                tokenA,
                tokenB,
                _type
            );
            _type = string.concat("Pearl Bribes: ", _poolStr);
            address _external_bribe = IBribeFactory(bribefactory).createBribe(
                owner(),
                tokenA,
                tokenB,
                _type
            );
            IERC20Upgradeable(base).approve(_gauge, type(uint256).max);
            internal_bribes[_gauge] = _internal_bribe;
            external_bribes[_gauge] = _external_bribe;
            gauges[_pool] = _gauge;
            poolForGauge[_gauge] = _pool;
            isGauge[_gauge] = true;
            isAlive[_gauge] = true;
            _updateFor(_gauge);
            pools.push(_pool);

            // update index
            supplyIndex[_gauge] = index; // new gauges are set to the default global state

            emit GaugeCreated(
                _gauge,
                msg.sender,
                _internal_bribe,
                _external_bribe,
                _pool
            );
        }
    }

    function increaseGaugeApprovals(address _gauge) external {
        require(msg.sender == emergencyCouncil);
        require(isGauge[_gauge] = true);
        IERC20Upgradeable(base).approve(_gauge, 0);
        IERC20Upgradeable(base).approve(_gauge, type(uint256).max);
    }

    function setNewBribe(
        address _gauge,
        address _internal,
        address _external
    ) external {
        require(msg.sender == emergencyCouncil);
        require(isGauge[_gauge] = true);
        internal_bribes[_gauge] = _internal;
        external_bribes[_gauge] = _external;
    }

    function setVotingEscrow(address _votingEscrow) external {
        require(msg.sender == governor);
        _ve = _votingEscrow;
    }

    // VE approval helpers

    function _isAuthorized(
        address owner,
        address spender,
        uint256 tokenId
    ) private view returns (bool) {
        return
            spender != address(0) &&
            (owner == spender ||
                IERC721(_ve).isApprovedForAll(owner, spender) ||
                IERC721(_ve).getApproved(tokenId) == spender);
    }

    function _checkAuthorized(
        address owner,
        address spender,
        uint256 tokenId
    ) private view {
        if (!_isAuthorized(owner, spender, tokenId)) {
            if (owner == address(0)) {
                revert("ERC721: owner query for nonexistent token");
            } else {
                revert("ERC721: caller is not owner nor approved");
            }
        }
    }
}
