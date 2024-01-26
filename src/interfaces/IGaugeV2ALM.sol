// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGaugeV2ALM {
  function initialize(
    address _rewardToken,
    address _almBox,
    address _gaugeCL,
    address _lBoxManager
  ) external;

  function createGauge(
    address rewardToken,
    address almBox,
    address gaugeCL,
    address lBoxManager
  ) external returns (address);

  function getBox() external view returns (address);

  function claimFees() external returns (uint256 claimed0, uint256 claimed1);

  function collectReward() external view returns (address);

  function rebalanceGaugeLiquidity(
    int24 newtickLower,
    int24 newtickUpper,
    uint128 burnLiquidity,
    uint128 mintLiquidity
  ) external;

  function pullGaugeLiquidity() external;

  ///@notice balance of a user
  function balanceOf(address account) external view returns (uint256);

  ///@notice total supply held
  function totalSupply() external view returns (uint256);

  ///@notice see earned rewards for user
  function earnedReward(address account) external view returns (uint256);

  ///@notice see earned fees by staked LP token
  function earnedFees()
    external
    view
    returns (uint256 amount0, uint256 amount1);

  ///@notice get amounts and liquidity for the staked lp token by an account
  function getStakedAmounts(
    address account
  ) external view returns (uint256, uint256, uint256);

  ///@notice set the alm box adreess
  function setBox(address almBox) external;
}
