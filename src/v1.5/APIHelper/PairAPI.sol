// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import "../../libraries/PositionValue.sol";
import "../../interfaces/IBribe.sol";
import "../../interfaces/IGaugeV2.sol";
import "../../interfaces/IGaugeV2ALM.sol";
import "../../interfaces/IVoter.sol";
import "../../interfaces/IVotingEscrow.sol";
import "../../interfaces/dex/IPearlV2Factory.sol";
import "../../interfaces/dex/IPearlV2Pool.sol";

import "../../interfaces/dex/IPearlV1Factory.sol";
import "../../interfaces/dex/IPearlV1Pool.sol";

import "../../interfaces/dex/INonfungiblePositionManager.sol";
import "../../interfaces/box/ILiquidBoxManager.sol";

contract PairAPI is Initializable {
    enum Version {
        V2,
        V3,
        V4
    }

    Version public version;

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

    struct feeInfo {
        uint256 tokenId; // nft token id
        uint256 token0; // token0 feeAmount for this tokenid
        uint256 token1; // token1 feeAmount for this tokenid
    }

    struct tokenBribe {
        address token;
        uint8 decimals;
        uint256 amount;
        string symbol;
    }

    struct pairBribeEpoch {
        uint256 epochTimestamp;
        uint256 totalVotes;
        address pair;
        tokenBribe[] bribes;
    }

    struct NftParams {
        address token0;
        address token1;
        uint24 fee;
        address pairToken0;
        address pairToken1;
        uint24 pairFee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    uint256 public constant MAX_PAIRS = 1000;
    uint256 public constant MAX_EPOCHS = 200;
    uint256 public constant MAX_REWARDS = 16;
    uint256 public constant WEEK = 7 * 24 * 60 * 60;

    IPearlV2Factory public pairFactory;
    IVoter public voter;

    INonfungiblePositionManager public positionManager;
    ILiquidBoxManager public lboxManager;
    IPearlV1Factory public pairFactoryV1;

    address public underlyingToken;
    address public owner;

    event Owner(address oldOwner, address newOwner);
    event Voter(address oldVoter, address newVoter);

    function initialize(
        address _intialOwner,
        address _voter,
        address _posManager,
        address _liquidBoxManager,
        address _factoryV1,
        address _underlyingToken
    ) public initializer {
        require(
            _intialOwner != address(0) &&
                _posManager != address(0) &&
                _factoryV1 != address(0) &&
                _underlyingToken != address(0),
            "!zero address"
        );

        owner = _intialOwner;

        voter = IVoter(_voter);
        positionManager = INonfungiblePositionManager(_posManager);
        lboxManager = ILiquidBoxManager(_liquidBoxManager);
        pairFactory = IPearlV2Factory(voter.factory());
        pairFactoryV1 = IPearlV1Factory(_factoryV1);
        underlyingToken = _underlyingToken;
    }

    function getAllPair(
        address _user,
        uint256 _amounts,
        uint256 _offset
    ) external view returns (pairInfo[] memory Pairs) {
        require(_amounts <= MAX_PAIRS, "too many pair");

        Pairs = new pairInfo[](_amounts);
        uint256 totV2Pairs = pairFactoryV1.allPairsLength();
        uint256 totV3Pairs = pairFactory.allPairsLength();

        address _pair;

        uint256 totPairs = totV2Pairs + totV3Pairs;
        uint256 j;
        for (uint256 i = _offset; i < _offset + _amounts; i++) {
            // if totalPairs is reached, break.
            if (i == totPairs) {
                break;
            }

            if (i < totV3Pairs) {
                _pair = pairFactory.allPairs(i);
                Pairs[i - _offset] = _pairAddressToInfoV3(_pair, _user);
            } else {
                _pair = pairFactoryV1.allPairs(j);
                Pairs[i - _offset] = _pairAddressToInfoV2(_pair, _user);
                j++;
            }
        }
    }

    function getPair(
        address _pair,
        address _account,
        uint8 _version
    ) external view returns (pairInfo memory _pairInfo) {
        if (_version == uint8(Version.V2)) {
            return _pairAddressToInfoV2(_pair, _account);
        }
        return _pairAddressToInfoV3(_pair, _account);
    }

    function _pairAddressToInfoV2(
        address _pair,
        address _account
    ) internal view returns (pairInfo memory _pairInfo) {
        IPearlV1Pool ipair = IPearlV1Pool(_pair);
        address token_0;
        address token_1;
        uint256 r0;
        uint256 r1;

        token_0 = ipair.token0();
        token_1 = ipair.token1();

        try IERC20MetadataUpgradeable(token_0).symbol() {} catch {
            return _pairInfo;
        }

        try IERC20MetadataUpgradeable(token_1).symbol() {} catch {
            return _pairInfo;
        }

        _pairInfo.version = Version.V2;

        (r0, r1, ) = ipair.getReserves();

        _pairInfo.pair_address = _pair;
        _pairInfo.symbol = string(
            abi.encodePacked(
                "aMM-",
                IERC20MetadataUpgradeable(token_0).symbol(),
                "/",
                IERC20MetadataUpgradeable(token_1).symbol()
            )
        );
        _pairInfo.decimals = ipair.decimals();
        _pairInfo.total_supply = ipair.totalSupply();
        // _pairInfo.claimable0 = ipair.claimable0(_account);
        // _pairInfo.claimable1 = ipair.claimable1(_account);

        // Token0 Info
        _pairInfo.token0 = token_0;
        _pairInfo.token0_decimals = IERC20MetadataUpgradeable(token_0)
            .decimals();
        _pairInfo.token0_symbol = IERC20MetadataUpgradeable(token_0).symbol();
        _pairInfo.total_supply0 = IERC20MetadataUpgradeable(token_0).balanceOf(
            _pair
        );
        // _pairInfo.reserve0 = r0;

        // Token1 Info
        _pairInfo.token1 = token_1;
        _pairInfo.token1_decimals = IERC20MetadataUpgradeable(token_1)
            .decimals();
        _pairInfo.token1_symbol = IERC20MetadataUpgradeable(token_1).symbol();
        _pairInfo.total_supply1 = IERC20MetadataUpgradeable(token_1).balanceOf(
            _pair
        );
        // _pairInfo.reserve1 = r1;

        // Account Info
        _pairInfo.account_lp_balance = IERC20Upgradeable(_pair).balanceOf(
            _account
        );
        _pairInfo.account_token0_balance = IERC20Upgradeable(token_0).balanceOf(
            _account
        );
        _pairInfo.account_token1_balance = IERC20Upgradeable(token_1).balanceOf(
            _account
        );

        if (_pairInfo.total_supply != 0) {
            _pairInfo.account_lp_amount0 =
                (r0 * _pairInfo.account_lp_balance) /
                _pairInfo.total_supply;

            _pairInfo.account_lp_amount1 =
                (r1 * _pairInfo.account_lp_balance) /
                _pairInfo.total_supply;
        }
    }

    function _pairAddressToInfoV3(
        address _pair,
        address _account
    ) internal view returns (pairInfo memory _pairInfo) {
        IPearlV2Pool ipair = IPearlV2Pool(_pair);
        address token_0;
        address token_1;
        uint256 r0;
        uint256 r1;

        _pairInfo.version = Version.V3;

        token_0 = ipair.token0();
        token_1 = ipair.token1();

        try IERC20MetadataUpgradeable(token_0).symbol() {} catch {
            return _pairInfo;
        }

        try IERC20MetadataUpgradeable(token_1).symbol() {} catch {
            return _pairInfo;
        }

        r0 = ipair.reserve0();
        r1 = ipair.reserve1();

        IGaugeV2 _gauge = IGaugeV2(voter.gauges(_pair));

        uint256 accountGaugeLPAmount = 0;
        uint256 gaugeAlmTotalSupply = 0;
        uint256 emissions = 0;
        {
            if (address(_gauge) != address(0)) {
                IGaugeV2ALM _gaugeAlm = IGaugeV2ALM(_gauge.gaugeAlm());

                _pairInfo.gauge = address(_gauge);
                _pairInfo.gauge_alm = address(_gaugeAlm);
                (, , emissions, , , , ) = _gauge.rewardsInfo();
                (
                    _pairInfo.gauge_fee_claimable0,
                    _pairInfo.gauge_fee_claimable1
                ) = _gauge.feeAmount();

                if (
                    address(_gaugeAlm) != address(0) &&
                    _gaugeAlm.balanceOf(_account) > 0
                ) {
                    gaugeAlmTotalSupply = _gaugeAlm.totalSupply();
                    _pairInfo.account_lp_alm_staked = _gaugeAlm.balanceOf(
                        _account
                    );
                    (
                        _pairInfo.account_lp_alm_staked_amount0,
                        _pairInfo.account_lp_alm_staked_amount1,

                    ) = _gaugeAlm.getStakedAmounts(_account);
                    _pairInfo.account_lp_alm_earned = _gaugeAlm.earnedReward(
                        _account
                    );

                    (uint256 claimable0, uint256 claimable1) = _gaugeAlm
                        .earnedFees();
                    _pairInfo.gauge_fee_claimable0 += claimable0;
                    _pairInfo.gauge_fee_claimable1 += claimable1;
                }
            }
        }

        // Pair General Info
        _pairInfo.pair_address = _pair;
        _pairInfo.symbol = string(
            abi.encodePacked(
                "aMM-",
                IERC20MetadataUpgradeable(token_0).symbol(),
                "/",
                IERC20MetadataUpgradeable(token_1).symbol()
            )
        );
        _pairInfo.name = _pairInfo.symbol;
        // _pairInfo.decimals = ipair.decimals();
        // _pairInfo.stable = ipair.stable();
        // _pairInfo.total_supply = ipair.liquidity();

        // Account positions
        _pairInfo = _positionInfo(_pairInfo, _account, _pair, ipair, _gauge);
        // Token0 Info
        _pairInfo.token0 = token_0;
        _pairInfo.token0_decimals = IERC20MetadataUpgradeable(token_0)
            .decimals();
        _pairInfo.token0_symbol = IERC20MetadataUpgradeable(token_0).symbol();
        _pairInfo.total_supply0 = IERC20MetadataUpgradeable(token_0).balanceOf(
            _pair
        );
        // _pairInfo.reserve0 = r0;
        // _pairInfo.tokenOwed = ipair.claimable0(_account);

        // Token1 Info
        _pairInfo.token1 = token_1;
        _pairInfo.token1_decimals = IERC20MetadataUpgradeable(token_1)
            .decimals();
        _pairInfo.token1_symbol = IERC20MetadataUpgradeable(token_1).symbol();
        _pairInfo.total_supply1 = IERC20MetadataUpgradeable(token_1).balanceOf(
            _pair
        );
        // _pairInfo.reserve1 = r1;
        // _pairInfo.tokenOwed1 = ipair.claimable1(_account);

        _pairInfo.fee = ipair.fee();

        // Pair's gauge Info

        _pairInfo.gauge_alm_total_supply = gaugeAlmTotalSupply;
        _pairInfo.emissions = emissions;
        _pairInfo.emissions_token = underlyingToken;
        _pairInfo.emissions_token_decimals = IERC20MetadataUpgradeable(
            underlyingToken
        ).decimals();

        // external address
        _pairInfo.gauge_fee = voter.internal_bribes(address(_gauge));
        _pairInfo.bribe = voter.external_bribes(address(_gauge));

        // Account Info
        _pairInfo.account_token0_balance = IERC20Upgradeable(token_0).balanceOf(
            _account
        );
        _pairInfo.account_token1_balance = IERC20Upgradeable(token_1).balanceOf(
            _account
        );
        _pairInfo.account_gauge_balance = accountGaugeLPAmount;
    }

    function _positionInfo(
        pairInfo memory _pairInfo,
        address _account,
        address _pair,
        IPearlV2Pool ipair,
        IGaugeV2 _gauge
    ) internal view returns (pairInfo memory) {
        NftParams memory nftParams;
        nftParams.pairToken0 = ipair.token0();
        nftParams.pairToken1 = ipair.token1();
        nftParams.pairFee = ipair.fee();

        address box = lboxManager.getBox(
            nftParams.pairToken0,
            nftParams.pairToken1,
            nftParams.pairFee
        );

        _pairInfo.box_address = box;
        _pairInfo.box_manager_address = address(lboxManager);

        //Add liquidity,ticks and sqrtPriceX96
        _pairInfo.total_liquidity = IPearlV2Pool(_pair).liquidity();
        (_pairInfo.sqrtPriceX96, _pairInfo.tick, , , , , ) = IPearlV2Pool(_pair)
            .slot0();

        if (box != address(0)) {
            _pairInfo.account_lp_alm = lboxManager.balanceOf(box, _account);
            if (_pairInfo.account_lp_alm > 0) {
                (
                    _pairInfo.account_lp_alm_claimable0,
                    _pairInfo.account_lp_alm_claimable1
                ) = lboxManager.getClaimableFees(box, _account);
            }

            (_pairInfo.alm_lower, _pairInfo.alm_upper) = lboxManager.getLimits(
                box
            );

            (
                _pairInfo.alm_total_supply0,
                _pairInfo.alm_total_supply1,
                ,
                ,
                _pairInfo.alm_total_liquidity
            ) = lboxManager.getTotalAmounts(box);

            //Account ALM amounts info
            (
                _pairInfo.account_lp_alm_amount0,
                _pairInfo.account_lp_alm_amount1,

            ) = lboxManager.getSharesAmount(box, _account);

            //Add ALM amounts to the total account lp amounts
            _pairInfo.account_lp_amount0 = _pairInfo.account_lp_alm_amount0;
            _pairInfo.account_lp_amount1 = _pairInfo.account_lp_alm_amount1;
        }

        //Get NFT liquidity info
        uint256 totalNftInUserAccount = IERC721Enumerable(
            address(positionManager)
        ).balanceOf(_account);

        uint256 totalNFT = totalNftInUserAccount;
        //Add staked nft tokenIds
        if (address(_gauge) != address(0)) {
            totalNFT += _gauge.balanceOf(_account);
        }

        if (totalNFT > 0) {
            uint128 j = 0;
            uint128 i = 0;
            _pairInfo.account_positions = new positionInfo[](totalNFT);
            {
                for (i = 0; i < totalNftInUserAccount; i++) {
                    uint256 tokenId = IERC721Enumerable(
                        address(positionManager)
                    ).tokenOfOwnerByIndex(_account, i);
                    (
                        ,
                        ,
                        nftParams.token0,
                        nftParams.token1,
                        nftParams.fee,
                        ,
                        ,
                        ,
                        ,
                        ,
                        ,

                    ) = positionManager.positions(tokenId);
                    if (
                        nftParams.token0 == nftParams.pairToken0 &&
                        nftParams.token1 == nftParams.pairToken1 &&
                        nftParams.fee == nftParams.pairFee
                    ) {
                        _pairInfo.account_positions[j] = _positions(
                            tokenId,
                            _pairInfo.sqrtPriceX96
                        );
                        _pairInfo.account_lp_amount0 += _pairInfo
                            .account_positions[j]
                            .amount0;
                        _pairInfo.account_lp_amount1 += _pairInfo
                            .account_positions[j]
                            .amount1;
                        j++;
                    }
                }
            }

            {
                //staked NFT details
                if (address(_gauge) != address(0)) {
                    totalNFT = _gauge.balanceOf(_account);
                    for (i = 0; i < totalNFT; i++) {
                        uint256 tokenId = _gauge.tokenOfOwnerByIndex(
                            _account,
                            i
                        );

                        _pairInfo.account_positions[j] = _positions(
                            tokenId,
                            _pairInfo.sqrtPriceX96
                        );
                        _pairInfo.account_lp_amount0 += _pairInfo
                            .account_positions[j]
                            .amount0;
                        _pairInfo.account_lp_amount1 += _pairInfo
                            .account_positions[j]
                            .amount1;
                        //mark nft as sstaked
                        _pairInfo.account_positions[j].isStaked = true;
                        _pairInfo.account_positions[j].earned = _gauge
                            .getReward(_account, tokenId);
                        j++;
                    }
                }
            }
        }
        return _pairInfo;
    }

    function _positions(
        uint256 tokenId,
        uint160 sqrtPriceX96
    ) internal view returns (positionInfo memory _pos) {
        _pos.tokenId = tokenId;
        (
            ,
            ,
            ,
            ,
            ,
            _pos.tickLower,
            _pos.tickUpper,
            _pos.liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);
        (_pos.amount0, _pos.amount1) = PositionValue.principal(
            positionManager,
            tokenId,
            sqrtPriceX96
        );

        (_pos.fee_amount0, _pos.fee_amount1) = PositionValue.fees(
            positionManager,
            tokenId
        );
    }

    function getPairBribe(
        uint256 _amounts,
        uint256 _offset,
        address _pair
    ) external view returns (pairBribeEpoch[] memory _pairEpoch) {
        require(_amounts <= MAX_EPOCHS, "too many epochs");

        _pairEpoch = new pairBribeEpoch[](_amounts);

        address _gauge = voter.gauges(_pair);

        IBribe bribe = IBribe(voter.external_bribes(_gauge));

        // check bribe and checkpoints exists
        if (address(0) == address(bribe)) {
            return _pairEpoch;
        }

        // scan bribes
        // get latest balance and epoch start for bribes
        uint256 _epochStartTimestamp = bribe.firstBribeTimestamp();

        // if 0 then no bribe created so far
        if (_epochStartTimestamp == 0) {
            return _pairEpoch;
        }

        uint256 _supply;

        for (uint256 i = _offset; i < _offset + _amounts; i++) {
            _supply = bribe.totalSupplyAt(_epochStartTimestamp);
            _pairEpoch[i - _offset].epochTimestamp = _epochStartTimestamp;
            _pairEpoch[i - _offset].pair = _pair;
            _pairEpoch[i - _offset].totalVotes = _supply;
            _pairEpoch[i - _offset].bribes = _bribe(
                _epochStartTimestamp,
                address(bribe)
            );

            _epochStartTimestamp += WEEK;
        }
    }

    function _bribe(
        uint256 _ts,
        address _br
    ) internal view returns (tokenBribe[] memory _tb) {
        IBribe _wb = IBribe(_br);
        uint256 tokenLen = _wb.rewardsListLength();

        _tb = new tokenBribe[](tokenLen);

        uint256 k;
        uint256 _rewPerEpoch;
        IERC20MetadataUpgradeable _t;
        for (k = 0; k < tokenLen; k++) {
            _t = IERC20MetadataUpgradeable(_wb.rewardTokens(k));
            IBribe.Reward memory _reward = _wb.rewardData(address(_t), _ts);
            _rewPerEpoch = _reward.rewardsPerEpoch;
            if (_rewPerEpoch > 0) {
                _tb[k].token = address(_t);
                _tb[k].symbol = _t.symbol();
                _tb[k].decimals = _t.decimals();
                _tb[k].amount = _rewPerEpoch;
            } else {
                _tb[k].token = address(_t);
                _tb[k].symbol = _t.symbol();
                _tb[k].decimals = _t.decimals();
                _tb[k].amount = 0;
            }
        }
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, "not owner");
        require(_owner != address(0), "zeroAddr");
        owner = _owner;
        emit Owner(msg.sender, _owner);
    }

    function setVoter(address _voter) external {
        require(msg.sender == owner, "not owner");
        require(_voter != address(0), "zeroAddr");
        address _oldVoter = address(voter);
        voter = IVoter(_voter);

        // update variable depending on voter
        pairFactory = IPearlV2Factory(voter.factory());
        underlyingToken = address(IVotingEscrow(voter._ve()).lockedToken());

        emit Voter(_oldVoter, _voter);
    }

    function setPositionManager(address _posManager) external {
        require(msg.sender == owner, "not owner");
        positionManager = INonfungiblePositionManager(_posManager);
    }

    function setBoxManager(address _liquidBoxManager) external {
        require(msg.sender == owner, "not owner");
        lboxManager = ILiquidBoxManager(_liquidBoxManager);
    }

    function left(
        address _pair,
        address _token
    ) external view returns (uint256 _rewPerEpoch) {
        address _gauge = voter.gauges(_pair);
        IBribe bribe = IBribe(voter.internal_bribes(_gauge));

        uint256 _ts = bribe.getEpochStart();
        IBribe.Reward memory _reward = bribe.rewardData(_token, _ts);
        _rewPerEpoch = _reward.rewardsPerEpoch;
    }

    function getGaugeTVL(
        address _pair,
        uint256[] memory tokenIds
    ) external view returns (uint256 amount0, uint256 amount1) {
        uint256 len = tokenIds.length;
        (uint160 sqrtPriceX96, , , , , , ) = IPearlV2Pool(_pair).slot0();

        for (uint256 i; i < len; i++) {
            uint256 tokenId = tokenIds[i];
            (uint256 _amount0, uint256 _amount1) = PositionValue.principal(
                positionManager,
                tokenId,
                sqrtPriceX96
            );
            amount0 += _amount0;
            amount1 += _amount1;
        }
    }
}
