// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "../../interfaces/IBribe.sol";
import "../../interfaces/dex/IPearlV2Pool.sol";
import "../../interfaces/dex/IPearlV2Factory.sol";
import "../../interfaces/IVoter.sol";
import "../../interfaces/IVotingEscrow.sol";
import "../../interfaces/IRewardsDistributor.sol";
import "./interfaces/IPearlV2PoolAPI.sol";
import "./interfaces/IVesting.sol";

contract veNFTAPI is Initializable {
    struct PairVotes {
        address pair;
        uint256 weight;
    }

    struct Vote {
        string tokenSymbol;
        uint256 tokenDecimals;
        uint256 voting_amount;
        bool voted;
        veNFT[] venft;
        PairVotes[] votes;
    }

    struct veNFT {
        uint256 id;
        uint128 amount;
        uint256 rebase_amount;
        uint256 lockEnd;
        uint256 vote_ts;
        address account;
        address token;
    }

    struct Reward {
        uint256 id;
        uint256 amount;
        uint8 decimals;
        address pair;
        address token;
        address fee;
        address bribe;
        string symbol;
    }

    struct AllPairRewards {
        Reward[] rewards;
    }

    uint256 public constant MAX_RESULTS = 1_000;
    uint256 public constant MAX_PAIRS = 30;

    address public owner;

    address public pairAPI;
    address public underlyingToken;

    IVoter public voter;
    IVotingEscrow public ve;
    IRewardsDistributor public rewardDistributor;
    IPearlV2Factory public pairFactory;

    mapping(address => bool) public notReward;

    event OwnerChanged(address indexed oldOwner, address newOwner);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _intialOwner,
        address _voter,
        address _rewarddistro,
        address _pairApi,
        address _pairFactory
    ) public initializer {
        require(
            _intialOwner != address(0) &&
                _voter != address(0) &&
                _rewarddistro != address(0) &&
                _pairApi != address(0) &&
                _pairFactory != address(0),
            "zeroAddr"
        );
        owner = _intialOwner;
        emit OwnerChanged(msg.sender, _intialOwner);
        pairAPI = _pairApi;
        voter = IVoter(_voter);
        rewardDistributor = IRewardsDistributor(_rewarddistro);
        require(address(rewardDistributor.ve()) == voter.ve(), "ve!=ve");
        ve = rewardDistributor.ve();
        underlyingToken = address(ve.lockedToken());
        pairFactory = IPearlV2Factory(_pairFactory);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function getNFTFromId(uint256 id) external view returns (veNFT memory) {
        return _getNFTFromId(id, ve.ownerOf(id));
    }

    function getNFTFromAddress(
        address _account
    ) external view returns (Vote memory vote) {
        uint256 _id;
        uint256 totNFTs = ve.balanceOf(_account);

        vote.venft = new veNFT[](totNFTs);

        for (uint i = totNFTs; i != 0; ) {
            unchecked {
                --i;
            }
            _id = ve.tokenOfOwnerByIndex(_account, i);
            if (_id != 0) {
                vote.venft[i] = _getNFTFromId(_id, _account);
            }
        }

        uint256 _totalPoolVotes = voter.poolVoteLength(_account);
        PairVotes[] memory votes = new PairVotes[](_totalPoolVotes);

        uint256 _poolWeight;
        address _votedPair;

        for (uint256 k = _totalPoolVotes; k != 0; ) {
            unchecked {
                --k;
            }
            _votedPair = voter.poolVote(_account, k);
            if (_votedPair != address(0)) {
                _poolWeight = voter.votes(_account, _votedPair);
                votes[k].pair = _votedPair;
                votes[k].weight = _poolWeight;
            }
        }

        vote.votes = votes;
        vote.voting_amount = ve.getVotes(_account);
        vote.tokenSymbol = IERC20MetadataUpgradeable(address(ve.lockedToken()))
            .symbol();
        vote.tokenDecimals = IERC20MetadataUpgradeable(
            address(ve.lockedToken())
        ).decimals();
        vote.voted = voter.hasVoted(_account);
    }

    function getVotingPowerFromAddress(
        address _account
    ) external view returns (uint256 _votingPower) {
        return ve.getVotes(_account);
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner == msg.sender, "!owner");
    }

    function _getNFTFromId(
        uint256 tokenId,
        address _account
    ) internal view returns (veNFT memory venft) {
        if (_account == address(0)) {
            return venft;
        }

        venft.id = tokenId;
        venft.account = _account;
        venft.amount = uint128(ve.getLockedAmount(tokenId));
        // venft.rebase_amount = rewardDistributor.claimable(tokenId);
        venft.vote_ts = voter.lastVoted(_account);
        venft.token = address(ve.lockedToken());

        address vestingContract = ve.vestingContract();
        if (_account == vestingContract) {
            IVotingEscrow.VestingSchedule memory schedule = IVesting(
                vestingContract
            ).getSchedule(tokenId);
            venft.lockEnd = schedule.endTime;
        } else {
            venft.lockEnd =
                block.timestamp +
                ve.getRemainingVestingDuration(tokenId);
        }
    }

    function hasClaimableRewards(
        uint256 _tokenId
    ) external view returns (bool) {
        if (rewardDistributor.claimable(_tokenId) != 0) {
            return true;
        }

        uint256 _totalPairs = pairFactory.allPairsLength();
        address _account = ve.ownerOf(_tokenId);

        for (uint256 i; i < _totalPairs; ) {
            address _pair = pairFactory.allPairs(i);
            address _gauge = voter.gauges(_pair);

            if (_gauge != address(0)) {
                address t0 = IPearlV2Pool(_pair).token0();
                address t1 = IPearlV2Pool(_pair).token1();

                IPearlV2PoolAPI.pairInfo memory _pairApi = IPearlV2PoolAPI(
                    pairAPI
                ).getPair(_pair, address(0), uint8(IPearlV2PoolAPI.Version.V3));

                if (0 != IBribe(_pairApi.gauge_fee).earned(_account, t0))
                    return true;
                if (0 != IBribe(_pairApi.gauge_fee).earned(_account, t1))
                    return true;

                address wrappedBribe = _pairApi.bribe;

                if (wrappedBribe != address(0)) {
                    uint256 _totalBribeTokens = IBribe(wrappedBribe)
                        .rewardsListLength();

                    for (uint256 j = _totalBribeTokens; j != 0; ) {
                        unchecked {
                            --j;
                        }
                        address _token = IBribe(wrappedBribe).rewardTokens(j);
                        if (
                            0 !=
                            IBribe(wrappedBribe).earned(_account, _token) &&
                            !notReward[_token]
                        ) return true;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }
        return false;
    }

    function allPairRewards(
        uint256 _amount,
        uint256 _offset,
        address _account
    ) external view returns (AllPairRewards[] memory rewards) {
        rewards = new AllPairRewards[](MAX_PAIRS);

        uint256 totalPairs = pairFactory.allPairsLength();
        address _pair;

        for (uint256 i = _offset; i < _offset + _amount; i++) {
            if (i >= totalPairs) {
                break;
            }
            _pair = pairFactory.allPairs(i);
            rewards[i].rewards = _pairReward(_pair, _account);
        }
    }

    function singlePairReward(
        address _account,
        address _pair
    ) external view returns (Reward[] memory _reward) {
        return _pairReward(_pair, _account);
    }

    function _pairReward(
        address _pair,
        address _account
    ) internal view returns (Reward[] memory _reward) {
        if (_pair == address(0)) {
            return _reward;
        }

        IPearlV2PoolAPI.pairInfo memory _pairApi = IPearlV2PoolAPI(pairAPI)
            .getPair(_pair, _account, uint8(IPearlV2PoolAPI.Version.V3));

        address wrappedBribe = _pairApi.bribe;

        uint256 totBribeTokens = (wrappedBribe == address(0))
            ? 0
            : IBribe(wrappedBribe).rewardsListLength();

        uint256 bribeAmount;

        _reward = new Reward[](2 + totBribeTokens);

        address _gauge = (voter.gauges(_pair));

        if (_gauge == address(0)) {
            return _reward;
        }

        // address _account = ve.ownerOf(id);

        {
            address t0 = IPearlV2Pool(_pair).token0();
            address t1 = IPearlV2Pool(_pair).token1();
            uint256 _feeToken0 = IBribe(_pairApi.gauge_fee).earned(
                _account,
                t0
            );
            uint256 _feeToken1 = IBribe(_pairApi.gauge_fee).earned(
                _account,
                t1
            );
            if (_feeToken0 > 0) {
                _reward[0] = Reward({
                    id: 0,
                    pair: _pair,
                    amount: _feeToken0,
                    token: t0,
                    symbol: IERC20MetadataUpgradeable(t0).symbol(),
                    decimals: IERC20MetadataUpgradeable(t0).decimals(),
                    fee: voter.internal_bribes(address(_gauge)),
                    bribe: address(0)
                });
            }

            if (_feeToken1 > 0) {
                _reward[1] = Reward({
                    id: 0,
                    pair: _pair,
                    amount: _feeToken1,
                    token: t1,
                    symbol: IERC20MetadataUpgradeable(t1).symbol(),
                    decimals: IERC20MetadataUpgradeable(t1).decimals(),
                    fee: voter.internal_bribes(address(_gauge)),
                    bribe: address(0)
                });
            }

            //wrapped bribe point to Bribes.sol (ext bribe)
            if (wrappedBribe == address(0)) {
                return _reward;
            }
        }

        address _token;

        for (uint256 k; k < totBribeTokens; k++) {
            _token = IBribe(wrappedBribe).rewardTokens(k);
            bribeAmount = IBribe(wrappedBribe).earned(_account, _token);
            if (!notReward[_token]) {
                _reward[2 + k] = Reward({
                    id: 0,
                    pair: _pair,
                    amount: bribeAmount,
                    token: _token,
                    symbol: IERC20MetadataUpgradeable(_token).symbol(),
                    decimals: IERC20MetadataUpgradeable(_token).decimals(),
                    fee: address(0),
                    bribe: wrappedBribe
                });
            }
        }

        return _reward;
    }

    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "zeroAddr");
        owner = _owner;
        emit OwnerChanged(msg.sender, _owner);
    }

    function setVoter(address _voter) external onlyOwner {
        voter = IVoter(_voter);
    }

    function setRewardDistro(address _rewarddistro) external onlyOwner {
        rewardDistributor = IRewardsDistributor(_rewarddistro);
        require(address(rewardDistributor.ve()) == voter.ve(), "ve!=ve");

        ve = rewardDistributor.ve();
        underlyingToken = address(IVotingEscrow(ve).lockedToken());
    }

    function setPairAPI(address _pairApi) external onlyOwner {
        pairAPI = _pairApi;
    }

    function setPairFactory(address _pairFactory) external onlyOwner {
        pairFactory = IPearlV2Factory(_pairFactory);
    }

    function setVotingEscrow(address _votingEscrow) external onlyOwner {
        ve = IVotingEscrow(_votingEscrow);
    }
}
