// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {VotesUpgradeable} from "openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {ERC721Upgradeable} from "openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC721, IERC721Metadata} from "openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IVotes} from "openzeppelin/contracts/governance/utils/IVotes.sol";
import {NonblockingLzAppUpgradeable} from "./cross-chain/NonblockingLzAppUpgradeable.sol";

import "./interfaces/IBribe.sol";
import "./interfaces/IBribeFactory.sol";
import "./interfaces/IEpochController.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IGaugeV2.sol";
import "./interfaces/IGaugeV2Factory.sol";
import "./interfaces/dex/IPearlV2Pool.sol";
import "./interfaces/dex/IPearlV2Factory.sol";
import "./Epoch.sol";
import {console2 as console} from "forge-std/Test.sol";

contract Voter is IVoter, NonblockingLzAppUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bool public immutable isMainChain;

    uint256 public constant PRECISION = 10 ** 18;

    address public ustb;
    address public ve; // the ve token that governs these contracts
    address public factory; // the PairFactory
    address public base;
    address public gaugefactory;
    address public bribefactory;
    address public lBoxFactory;
    address public minter;
    address public governor; // should be set to an IGovernor
    address public emergencyCouncil; // credibly neutral party similar to Curve's Emergency DAO
    address public epochController;

    bytes public defaultAdapterParams;
    uint16 public lzMainChainId;
    uint16 public lzChainId;
    uint256 public totalWeight; // total voting weight

    address[] public pools; // all pools viable for incentives
    address[] public lzPools; // all pools viable for incentives

    uint256 public index;
    mapping(address => uint256) public supplyIndex;

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
    mapping(address => bool) public isBribe;
    mapping(address => uint256) public claimable;

    event Whitelisted(address indexed whitelister, address indexed token);
    event LzAdapterParamsEvent(uint256 indexed limit);
    event MinterChanged(address indexed _minter);
    event EpochCotrollerChanged(address indexed epochController);
    event GovernorChanged(address indexed governor);
    event EmergencyCouncilChanged(address indexed emergencyCouncil);

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
    event Deposit(address indexed lp, address indexed gauge, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed lp, address indexed gauge, uint256 tokenId, uint256 amount);
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);
    event DistributeReward(address indexed sender, address indexed gauge, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _mainChainId, address _lzEndpoint) NonblockingLzAppUpgradeable(_lzEndpoint) {
        isMainChain = _mainChainId == block.chainid;
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _emergencyCouncil,
        address __ve,
        address _lockedToken,
        address _pearlV2Factory,
        address _gaugesFactory,
        address _bribeFactory,
        address _ustb,
        uint16 _lzMainChainId,
        uint16 _lzChainId
    ) public initializer {
        require(
            _initialOwner != address(0) && _lockedToken != address(0) && _emergencyCouncil != address(0)
                && _pearlV2Factory != address(0) && _gaugesFactory != address(0) && _bribeFactory != address(0)
                && _ustb != address(0),
            "!zero address"
        );

        require(_lzMainChainId != 0 && _lzChainId != 0, "!lzChainId");

        __NonblockingLzApp_init();
        __ReentrancyGuard_init();
        _transferOwnership(_initialOwner);

        governor = _initialOwner;
        emergencyCouncil = _emergencyCouncil;

        // VotingEscrow is only deployed on main chain
        if (__ve != address(0)) {
            ve = __ve;
            require(_lockedToken == address(IVotingEscrow(__ve).lockedToken()), "!locked token");
        }

        factory = _pearlV2Factory;
        base = _lockedToken;
        gaugefactory = _gaugesFactory;
        bribefactory = _bribeFactory;
        ustb = _ustb;
        lzMainChainId = _lzMainChainId; //set layerzero chain id for protocol mainChain
        lzChainId = _lzChainId; //set layerzero chain id for protocol mainChain
        defaultAdapterParams = abi.encodePacked(uint16(1), uint256(3_000_000)); //set layerZero adapter params for native fees
    }

    modifier onlyGovernor() {
        require(msg.sender == governor, "governor");
        _;
    }

    modifier isAllowed() {
        _checkAllowed();
        _checkDistribution();
        _;
    }

    modifier isClaimAllowed() {
        _checkAllowed();
        _;
    }

    //=======================  INTERNAL  =========================================

    function _checkAllowed() internal view {
        require(isMainChain, "!mainChain");
    }

    function _checkDistribution() internal view {
        require(epochController != address(0), "!epochController");
        //voting is not allowed while distribution is running
        require(!IEpochController(epochController).checkDistribution(), "Voting is not allowed during distribution");
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
                uint256 _share = (_supplied * _delta) / PRECISION; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    function _reset(address account) internal {
        address[] storage _poolVote = poolVote[account];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt;) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[account][_pool];

            if (_votes != 0) {
                weights[_pool] -= _votes;
                votes[account][_pool] -= _votes;

                IBribe(internal_bribes[gauges[_pool]])._withdraw(uint256(_votes), account);
                IBribe(external_bribes[gauges[_pool]])._withdraw(uint256(_votes), account);
                _totalWeight += _votes;

                emit Abstained(account, _votes);
            }
            unchecked {
                i++;
            }
        }
        totalWeight -= _totalWeight;
        usedWeights[account] = 0;
        delete poolVote[account];
    }

    function _poke(address account) internal {
        address[] memory _poolVote = poolVote[account];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);
        for (uint256 i = _poolCnt; i != 0;) {
            unchecked {
                --i;
            }
            _weights[i] = votes[account][_poolVote[i]];
        }
        _vote(account, _poolVote, _weights);
    }

    function _distributeFess(address _gauge) internal {
        if (isAlive[_gauge] && IGaugeV2(_gauge).isMainChain() && IGaugeV2(_gauge).isForPair()) {
            IGaugeV2(_gauge).claimFees();
        }
    }

    function _vote(address account, address[] memory _poolVote, uint256[] memory _weights) internal {
        _reset(account);
        uint256 _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(ve).getVotes(account);
        uint256 _totalVoteWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = _poolCnt; i != 0;) {
            unchecked {
                --i;
            }

            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = _poolCnt; i != 0;) {
            unchecked {
                --i;
            }
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge] && isAlive[_gauge]) {
                uint256 _poolWeight = (_weights[i] * _weight) / _totalVoteWeight;

                require(votes[account][_pool] == 0, "zero votes");
                require(_poolWeight != 0, "zero weight");

                poolVote[account].push(_pool);

                weights[_pool] += _poolWeight;
                votes[account][_pool] += _poolWeight;

                IBribe(internal_bribes[_gauge])._deposit(uint256(_poolWeight), account);

                IBribe(external_bribes[_gauge])._deposit(uint256(_poolWeight), account);
                _usedWeight += _poolWeight;
                emit Voted(account, _poolWeight);
            }
        }

        if (_usedWeight != 0) {
            voted[account] = true;
        } else {
            voted[account] = false;
        }

        totalWeight += _usedWeight;
        usedWeights[account] = _usedWeight;
    }

    function _whitelist(address _token) internal {
        require(!isWhitelisted[_token], "already whitelisted");
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }

    // VE approval helpers
    function _isAuthorized(address owner, address spender, uint256 tokenId) private view returns (bool) {
        return spender != address(0)
            && (
                owner == spender || IERC721(ve).isApprovedForAll(owner, spender)
                    || IERC721(ve).getApproved(tokenId) == spender
            );
    }

    function _checkAuthorized(address owner, address spender, uint256 tokenId) private view {
        if (!_isAuthorized(owner, spender, tokenId)) {
            if (owner == address(0)) {
                revert("ERC721: owner query for nonexistent token");
            } else {
                revert("ERC721: caller is not owner nor approved");
            }
        }
    }

    function _createGauge(uint16 _LzPoolChainId, address _pool, address token0, address token1)
        internal
        returns (address)
    {
        require(gauges[_pool] == address(0), "exists");
        require(ustb != address(0), "!ustb ");
        address _internal_bribe;
        address _external_bribe;

        uint16 _lzMainChainId = lzMainChainId;

        //create internal bribe contract to collect LP fees
        string memory _type = "Pearl LP Fees";
        _internal_bribe = IBribeFactory(bribefactory).createBribe(
            _lzMainChainId, _LzPoolChainId, _pool, owner(), token0, token1, _type
        );
        isBribe[_internal_bribe] = true;

        //create external bribe
        _type = "Pearl Bribes";
        _external_bribe = IBribeFactory(bribefactory).createBribe(
            _lzMainChainId, _LzPoolChainId, _pool, owner(), token0, token1, _type
        );
        isBribe[_external_bribe] = true;

        (address _gauge, address _almGauge) = IGaugeV2Factory(gaugefactory).createGauge(
            _lzMainChainId,
            _LzPoolChainId,
            factory,
            _pool,
            base, //rewardToken
            address(this), //Distribution
            _internal_bribe,
            true
        );

        internal_bribes[_gauge] = _internal_bribe;
        external_bribes[_gauge] = _external_bribe;
        gauges[_pool] = _gauge;
        gaugesALM[_pool] = _almGauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        supplyIndex[_gauge] = index;
        pools.push(_pool);

        emit GaugeCreated(_gauge, msg.sender, _internal_bribe, _external_bribe, _pool);

        return _gauge;
    }

    //=======================  ACTION  =========================================

    /**
     * @notice Creates a new gauge for the specified pool.
     * @dev Emits a GaugeCreated event upon successful creation.
     * Adapter parameters should be provided if default parameters are overridden; otherwise, pass "".
     * _adapterParams = abi.encodePacked(uint16(1), 30000000);
     * @param _pool The address of the pool for which the gauge is created.
     * @param _adapterParams The adapter parameters required for Layerzero.
     * @return _gauge The address of the newly created gauge.
     */
    function createGauge(address _pool, bytes memory _adapterParams) external payable returns (address _gauge) {
        bool isPair = IPearlV2Factory(factory).isPair(_pool);
        require(isPair, "!pair");

        address tokenA = IPearlV2Pool(_pool).token0();
        address tokenB = IPearlV2Pool(_pool).token1();

        if (msg.sender != governor) {
            // gov can create for any pool, even non-Pearl pairs
            require(isPair, "!_pool");
            require(tokenA == ustb || tokenB == ustb, "!ustb");
        }

        //create gauge
        _gauge = _createGauge(lzChainId, _pool, tokenA, tokenB);

        // Set the gauge for reward distribution
        IPearlV2Factory(factory).setPoolGauge(_pool, _gauge);

        //notify main chain chain to create the child gauge for the pool
        if (!isMainChain) {
            _adapterParams = _adapterParams.length > 2 ? _adapterParams : defaultAdapterParams;
            bytes memory _payload = abi.encode(_pool);

            _lzSend(lzMainChainId, _payload, payable(msg.sender), address(0x0), _adapterParams, msg.value);
        }
    }

    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory, //srcAddress
        uint64, //nonce
        bytes memory payload
    ) internal virtual override {
        address _pool = abi.decode(payload, (address));
        //add pool to lzPool list
        lzPools.push(_pool);
        _createGauge(srcChainId, _pool, address(0), address(0));
    }

    function reset() external nonReentrant isAllowed {
        address account = msg.sender;
        lastVoted[account] = block.timestamp;
        _reset(account);
        voted[account] = false;
    }

    function poke() external nonReentrant isAllowed {
        _poke(msg.sender);
    }

    function poke(address account) external nonReentrant isAllowed {
        require(msg.sender == ve, "!ve");
        uint256 lastVotedEpoch = (lastVoted[account] / EPOCH_DURATION) * EPOCH_DURATION;
        uint256 currentEpoch = IMinter(minter).active_period();
        if (lastVotedEpoch < currentEpoch) return;
        _poke(account);
    }

    function vote(address[] memory _poolVote, uint256[] memory _weights) external nonReentrant isAllowed {
        address account = msg.sender;
        require(_poolVote.length == _weights.length, "length mismatch");
        lastVoted[account] = block.timestamp;
        _vote(account, _poolVote, _weights);
    }

    function whitelist(address _token) public onlyGovernor {
        _whitelist(_token);
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

    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external isClaimAllowed {
        for (uint256 i = _bribes.length; i != 0;) {
            unchecked {
                --i;
            }
            IBribe(_bribes[i]).getRewardForOwner(msg.sender, _tokens[i]);
        }
    }

    function claimFees(address[] memory _fees, address[][] memory _tokens) external isClaimAllowed {
        for (uint256 i = _fees.length; i != 0;) {
            unchecked {
                --i;
            }
            IBribe(_fees[i]).getRewardForOwner(msg.sender, _tokens[i]);
        }
    }

    function distributeFees(address[] memory _gauges) external {
        for (uint256 i = _gauges.length; i != 0;) {
            unchecked {
                --i;
            }
            _distributeFess(_gauges[i]);
        }
    }

    function distributeFees(uint256 start, uint256 finish) public {
        for (uint256 x = start; x < finish;) {
            address _gauge = gauges[pools[x]];
            _distributeFess(_gauge);
            unchecked {
                ++x;
            }
        }
    }

    function _distribute(address _gauge) internal {
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
                IERC20Upgradeable(base).forceApprove(_gauge, _claimable);
                IGaugeV2(_gauge).notifyRewardAmount(base, _claimable);
                emit DistributeReward(msg.sender, _gauge, _claimable);
            }
        }
    }

    function distributeAll() external {
        distribute(0, pools.length);
    }

    function distribute(uint256 start, uint256 finish) public nonReentrant {
        for (uint256 x = start; x < finish;) {
            _distribute(gauges[pools[x]]);
            unchecked {
                ++x;
            }
        }
    }

    function distribute(address[] memory _gauges) external nonReentrant {
        for (uint256 x = _gauges.length; x != 0;) {
            unchecked {
                --x;
            }
            _distribute(_gauges[x]);
        }
    }

    function notifyRewardAmount(uint256 amount) external {
        require(msg.sender == minter, "!minter");
        require(totalWeight != 0, "no votes");
        IERC20Upgradeable(base).safeTransferFrom(msg.sender, address(this), amount);
        uint256 _ratio = (amount * PRECISION) / totalWeight; // PRECISION adjustment is removed during claim

        if (_ratio != 0) {
            index += _ratio;
        }
        emit NotifyReward(msg.sender, base, amount);
    }

    //=======================  SET  =========================================

    function setGovernor(address _governor) public onlyOwner {
        governor = _governor;
        emit GovernorChanged(_governor);
    }

    function setEmergencyCouncil(address _council) public {
        require(msg.sender == emergencyCouncil, "sender not emergency council");
        emergencyCouncil = _council;
        emit EmergencyCouncilChanged(_council);
    }

    function setNewBribe(address _gauge, address _internal, address _external) external {
        require(msg.sender == emergencyCouncil, "sender not emergency council");
        require(isGauge[_gauge], "not gauge");
        internal_bribes[_gauge] = _internal;
        external_bribes[_gauge] = _external;
    }

    function setMinter(address _minter) public onlyOwner {
        minter = _minter;
        emit MinterChanged(_minter);
    }

    function setEpochController(address _epochControllerAddress) external onlyGovernor {
        epochController = _epochControllerAddress;
        emit EpochCotrollerChanged(_epochControllerAddress);
    }

    function whitelist(address[] memory _token) public onlyGovernor {
        for (uint256 i = _token.length; i != 0;) {
            unchecked {
                --i;
            }
            _whitelist(_token[i]);
        }
    }

    function setLzAdapterParams(uint256 _limit) public onlyOwner {
        require(_limit >= 200_000, "gasLimit");
        defaultAdapterParams = abi.encodePacked(uint16(1), _limit);
        emit LzAdapterParamsEvent(_limit);
    }

    //=======================  VIEW  =========================================

    function getIncentivizedPools() external view returns (address[] memory) {
        return pools;
    }

    function length() external view returns (uint256) {
        return pools.length;
    }

    function getLzPools() external view returns (address[] memory) {
        return lzPools;
    }

    function getLzPoolsLength() external view returns (uint256) {
        return lzPools.length;
    }

    function poolVoteLength(address account) external view returns (uint256) {
        return poolVote[account].length;
    }

    function hasVoted(address _account) external view returns (bool) {
        return voted[_account] && lastVoted[_account] >= IMinter(minter).active_period();
    }

    function estimateSendFee(address _pool, bool _useZro, bytes memory _adapterParams)
        public
        view
        returns (uint256 nativeFee, uint256 zroFee)
    {
        bytes memory _payload = abi.encode(_pool);
        uint16 _dstChainId = uint16(lzMainChainId);
        bytes memory trustedRemote = getTrustedRemote(_dstChainId);
        (address _dstAddress,) = abi.decode(trustedRemote, (address, address));

        _adapterParams = _adapterParams.length > 2 ? _adapterParams : defaultAdapterParams;

        return lzEndpoint.estimateFees(_dstChainId, _dstAddress, _payload, _useZro, _adapterParams);
    }
}
