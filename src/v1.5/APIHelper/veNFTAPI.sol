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

interface IVesting {
    function getSchedule(
        uint256 tokenId
    )
        external
        view
        returns (IVotingEscrow.VestingSchedule memory vestingSchedule);
}

interface IPearlV2PoolAPI {
    enum Version {
        V2,
        V3,
        V4
    }

    struct positionInfo {
        uint256 tokenId; // nft token id
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        uint256 fee_amount0; // token0 feeAmount for this tokenid
        uint256 fee_amount1; // token1 feeAmount for this tokenid
        uint256 earned;
        bool isStaked;
    }

    struct pairInfo {
        // pair info
        Version version;
        address pair_address; // pair contract address
        address box_address; // box contract address
        address box_manager_address; // box manager contract address
        string name; // pair name
        string symbol; // pair symbol
        uint256 decimals; //v1Pools LP token decimals
        address token0; // pair 1st token address
        address token1; // pair 2nd token address
        uint24 fee; // fee of the pair
        string token0_symbol; // pair 1st token symbol
        uint256 token0_decimals; // pair 1st token decimals
        string token1_symbol; // pair 2nd token symbol
        uint256 token1_decimals; // pair 2nd token decimals
        uint256 total_supply; // total supply of v1 pools
        uint256 total_supply0; // token0 available in pool
        uint256 total_supply1; // token1 available in pool
        uint128 total_liquidity; //liquidity of the pool
        uint160 sqrtPriceX96;
        int24 tick;
        // pairs gauge
        address gauge; // pair gauge address
        address gauge_alm; // pair gauge ALM address
        uint256 gauge_alm_total_supply; // pair staked tokens (less/eq than/to pair total supply)
        address gauge_fee; // pair fees contract address
        uint256 gauge_fee_claimable0; // fees claimable in token1
        uint256 gauge_fee_claimable1; // fees claimable in token1
        address bribe; // pair bribes contract address
        uint256 emissions; // pair emissions (per second) for active liquidity
        address emissions_token; // pair emissions token address
        uint256 emissions_token_decimals; // pair emissions token decimals
        //alm
        int24 alm_lower; //lower limit of the alm
        int24 alm_upper; //upper limit of the alm
        uint256 alm_total_supply0; // token0 available in alm
        uint256 alm_total_supply1; // token1 available in alm
        uint128 alm_total_liquidity; //liquidity of the alm
        // User deposit
        uint256 account_lp_balance; //v1Pools account LP tokens balance
        uint256 account_lp_amount0; // total amount of token0 available in pool including alm for account
        uint256 account_lp_amount1; //  total amount of token1 available in pool including alm for account
        uint256 account_lp_alm; // total amount of token0 available in pool including alm for account
        uint256 account_lp_alm_staked; // total amount of token0 available in pool including alm for account
        uint256 account_lp_alm_amount0; // amount of token0 available in alm for account
        uint256 account_lp_alm_amount1; //  amount of token1 available in alm for account
        uint256 account_lp_alm_staked_amount0; // amount of token1 for staked ALM LP token
        uint256 account_lp_alm_staked_amount1; // amount of token0 for stakedALM  LP token
        uint256 account_lp_alm_earned; // amount of rewards earned on stake ALM LP token
        uint256 account_lp_alm_claimable0; // total amount of token0 available in pool including alm for account
        uint256 account_lp_alm_claimable1; // total amount of token0 available in pool including alm for account
        uint256 account_token0_balance; // account 1st token balance
        uint256 account_token1_balance; // account 2nd token balance
        uint256 account_gauge_balance; // account pair staked in gauge balance
        positionInfo[] account_positions; //nft position information for account
    }

    function getPair(
        address _pair,
        address _account,
        uint8 _version
    ) external view returns (pairInfo memory _pairInfo);

    function pair_factory() external view returns (address);
}

contract veNFTAPI is Initializable {
    struct pairVotes {
        address pair;
        uint256 weight;
    }

    struct Vote {
        string tokenSymbol;
        uint256 tokenDecimals;
        uint256 voting_amount;
        bool voted;
        veNFT[] venft;
        pairVotes[] votes;
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

    uint256 public constant MAX_RESULTS = 1000;
    uint256 public constant MAX_PAIRS = 30;

    IVoter public voter;
    address public underlyingToken;

    mapping(address => bool) public notReward;

    IVotingEscrow public ve;
    IRewardsDistributor public rewardDistributor;

    address public pairAPI;
    IPearlV2Factory public pairFactory;

    address public owner;
    event Owner(address oldOwner, address newOwner);

    struct AllPairRewards {
        Reward[] rewards;
    }

    constructor() {}

    function initialize(
        address _voter,
        address _rewarddistro,
        address _pairApi,
        address _pairFactory
    ) public initializer {
        owner = msg.sender;

        pairAPI = _pairApi;
        voter = IVoter(_voter);
        rewardDistributor = IRewardsDistributor(_rewarddistro);

        require(address(rewardDistributor.ve()) == voter._ve(), "ve!=ve");

        ve = rewardDistributor.ve();
        underlyingToken = address(ve.lockedToken());
        pairFactory = IPearlV2Factory(_pairFactory);
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
        pairVotes[] memory votes = new pairVotes[](_totalPoolVotes);

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
        venft.rebase_amount = rewardDistributor.claimable(tokenId);
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

        for (uint256 i = 0; i < _totalPairs; ) {
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

        uint256 i = _offset;
        address _pair;
        for (i; i < _offset + _amount; i++) {
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

        uint256 k = 0;
        address _token;

        for (k; k < totBribeTokens; k++) {
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

    function setOwner(address _owner) external {
        require(msg.sender == owner, "not owner");
        require(_owner != address(0), "zeroAddr");
        owner = _owner;
        emit Owner(msg.sender, _owner);
    }

    function setVoter(address _voter) external {
        require(msg.sender == owner);

        voter = IVoter(_voter);
    }

    function setRewardDistro(address _rewarddistro) external {
        require(msg.sender == owner);

        rewardDistributor = IRewardsDistributor(_rewarddistro);
        require(address(rewardDistributor.ve()) == voter._ve(), "ve!=ve");

        ve = rewardDistributor.ve();
        underlyingToken = address(IVotingEscrow(ve).lockedToken());
    }

    function setPairAPI(address _pairApi) external {
        require(msg.sender == owner);
        pairAPI = _pairApi;
    }

    function setPairFactory(address _pairFactory) external {
        require(msg.sender == owner);
        pairFactory = IPearlV2Factory(_pairFactory);
    }

    function setVotingEscrow(address _votingEscrow) external {
        require(msg.sender == owner);
        ve = IVotingEscrow(_votingEscrow);
    }
}
