// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

    function getPair(address _pair, address _account, uint8 _version)
        external
        view
        returns (pairInfo memory _pairInfo);

    function pair_factory() external view returns (address);
}
