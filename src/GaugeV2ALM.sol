// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin/contracts/utils/math/Math.sol";
import "openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IBribe.sol";
import "./interfaces/IGaugeV2.sol";
import "./interfaces/box/ILiquidBoxMinimal.sol";

/**
 * @title Active Liquidity Management Gauge for Concentrated Liquidity Pools
 * @author Maverick
 * @notice This Solidity Gauge contract manages ERC20 LP tokens staking for PearlV3 Concentrated Liquidity Pools.
 * The contract claims reward from master gauge contract using the `secondsPerActiveLiquidity` metric
 * to fairly distribute rewards among liquidity providers, incentivizing active participation within the specified pools.
 * Additionally, collected fees from staked LP tokens are distributed as internal bribes to incentivize voters
 * participating in governance or decision-making processes related to the liquidity management.
 * Liquidity providers earn rewards based on the duration and quantity of active liquidity they contribute,
 * while participants in governance receive internal bribes from collected fees.
 * For detailed function descriptions and reward distribution mechanisms, refer to protocol documentaion.
 */

contract GaugeV2ALM is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     *
     *  NON UPGRADEABLE STORAGE
     *
     */

    //fix value as alm doesn't hold any NFT
    uint8 public constant decimals = 18;
    uint256 public constant TOKENID = 1409;
    uint256 public constant PRECISION = 1e36;

    IERC20Upgradeable public rewardToken;
    IGaugeV2 public gaugeCL;
    ILiquidBoxMinimal public box;

    int24 tickLower;
    int24 tickUpper;
    uint128 public liquidity;

    uint256 public _totalSupply;
    uint256 public rewardPerTokenStored;

    address lBoxManager;
    uint256 public lastUpdateTime;
    /**
     *
     *  EVENTS
     *
     */

    mapping(address => uint256) public _balances;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 reward);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _rewardToken, address _almBox, address _gaugeCL, address _lBoxManager)
        public
        initializer
    {
        __Ownable_init();
        __ReentrancyGuard_init();
        rewardToken = IERC20Upgradeable(_rewardToken); // main reward
        box = ILiquidBoxMinimal(_almBox);
        gaugeCL = IGaugeV2(_gaugeCL);
        lBoxManager = _lBoxManager;
    }

    //============================== MODIFIERS ==================================

    modifier updateReward(address account) {
        _pullRewardFromGauge();
        if (account != address(0)) {
            rewards[account] = earnedReward(account);
            userRewardPerTokenPaid[account] = rewardPerToken();
        }
        _;
    }

    //============================== SET ==================================

    function setBox(address _almBox) external onlyOwner {
        require(_almBox != address(0), "box");
        box = ILiquidBoxMinimal(_almBox);
    }

    //============================== INTERNAL ==================================

    ///@notice deposit internal
    function _deposit(uint256 amount, address owner) internal nonReentrant updateReward(owner) {
        require(amount > 0, "deposit(Gauge): cannot stake 0");

        _balances[owner] = _balances[owner].add(amount);
        _totalSupply = _totalSupply.add(amount);
        box.transferFrom(owner, address(this), amount);

        _updateLiquidity(0, 0);

        emit Deposit(owner, amount);
    }

    ///@notice withdraw internal
    function _withdraw(uint256 amount, address owner) internal nonReentrant updateReward(owner) {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[owner] >= amount, "LB");
        require(_totalSupply >= amount, "supply");

        unchecked {
            _totalSupply = _totalSupply.sub(amount);
            _balances[owner] = _balances[owner].sub(amount);
        }

        _updateLiquidity(0, 0);

        box.transfer(owner, amount);
        emit Withdraw(owner, amount);
    }

    function _updateLiquidity(int24 _newTickLower, int24 _newTickUpper) internal {
        // Trident liquidity per share is updated when tokens are depositied / withdrawn in the
        // in the Trident ALM. Since liquidityPerShare is updated in the ALM, gauge must withdraw
        // the locked liquidity, collect reward and re-enter with latest staked liquidity.
        uint128 _currentLiquidity = liquidity;
        uint256 _liquidityPerShare = box.getPoolLiquidityPerShare();
        uint128 _newLiquidity = _getLatestStakedLiquidity(_liquidityPerShare);

        //if liquidity is being deployed in same tick ranges
        int24 _tickLower = tickLower;
        int24 _tickUpper = tickUpper;

        //if liquidity is being deployed in same tick ranges
        if (_newTickLower == 0 && _newTickUpper == 0) {
            _newTickLower = _tickLower;
            _newTickUpper = _tickUpper;
        }

        //pull the current liquidity from the gauge
        if (_currentLiquidity > 0) {
            gaugeCL.notifyERC20Withdraw(_tickLower, _tickUpper, _currentLiquidity);
        }

        //deploy new liquidity in the gauge
        if (_newLiquidity > 0) {
            gaugeCL.notifyERC20Deposit(_newTickLower, _newTickUpper, _newLiquidity);
        }

        //update the new liquidity info
        liquidity = _newLiquidity;
        if (_tickLower != _newTickLower) tickLower = _newTickLower;
        if (_tickUpper != _newTickUpper) tickUpper = _newTickUpper;
    }

    //pull reward from CL gauge
    function _pullRewardFromGauge() internal {
        if ((block.timestamp - lastUpdateTime) == 0) return; // only once per block
        if (liquidity != 0) {
            //collect reward from the CL gauge
            uint256 amount = gaugeCL.collectRewardForALM(box.baseLower(), box.baseUpper());
            if (amount > 0) {
                rewardPerTokenStored = (rewardPerTokenStored.add(amount.mulDiv(PRECISION, _totalSupply)));
            }
        }
        lastUpdateTime = block.timestamp;
    }

    function _getLatestStakedLiquidity(uint256 _liquidityPerShare) internal view returns (uint128) {
        return uint128(_totalSupply.mulDiv(_liquidityPerShare, PRECISION));
    }

    //============================== ACTION ==================================

    ///@notice deposit amount TOKEN
    function deposit(uint256 amount) external {
        _deposit(amount, msg.sender);
    }

    ///@notice withdraw a certain amount of TOKEN
    function withdraw(uint256 amount) external {
        _withdraw(amount, msg.sender);
    }

    ///@notice User harvest function
    function collectReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit Harvest(msg.sender, reward);
        }
    }

    ///@notice transfer staked lp fee to the gaugeV2_CL
    function claimFees() external nonReentrant returns (uint256 claimed0, uint256 claimed1) {
        // fees are update before transfer of lp tokens
        if (lBoxManager != address(0) && address(box) != address(0)) {
            return ILiquidBoxMinimal(lBoxManager).claimFees(address(box), address(gaugeCL));
        }
    }

    function rebalanceGaugeLiquidity(
        int24 newtickLower,
        int24 newtickUpper,
        uint128 burnLiquidity,
        uint128 mintLiquidity
    ) external nonReentrant {
        require(address(box) == msg.sender, "box");
        _updateLiquidity(newtickLower, newtickUpper);
    }

    function pullGaugeLiquidity() external nonReentrant {
        require(address(box) == msg.sender);
        require(box.getPoolLiquidityPerShare() == 0, "liquidity");
        _updateLiquidity(0, 0);
    }

    //============================== VIEW ==================================

    ///@notice total supply held
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    ///@notice balance of a user
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function getBox() external view returns (address) {
        return address(box);
    }

    ///@notice reward for a single token
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply != 0) {
            uint256 amount = gaugeCL.getRewardForALM(box.baseLower(), box.baseUpper());
            return rewardPerTokenStored.add(amount.mulDiv(PRECISION, _totalSupply));
        }
        return rewardPerTokenStored;
    }

    ///@notice see earned rewards for user
    function earnedReward(address account) public view returns (uint256) {
        return _balances[account].mulDiv(rewardPerToken().sub(userRewardPerTokenPaid[account]), PRECISION).add(
            rewards[account]
        );
    }

    ///@notice see earned rewards for user
    function earnedFees() public view returns (uint256 amount0, uint256 amount1) {
        return box.earnedFees(address(this));
    }

    ///@notice get amounts and liquidity for the staked lp token by an account
    function getStakedAmounts(address account) external view returns (uint256, uint256, uint256) {
        return box.getSharesAmount(_balances[account]);
    }
}
