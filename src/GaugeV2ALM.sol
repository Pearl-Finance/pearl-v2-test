// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin/contracts/utils/math/Math.sol";

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

contract GaugeV2ALM is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
    uint256 public constant PRECISION = 10 ** 36;
    uint256 public constant ONE_HUNDRED_FEE = 1_000_000; // 100%
    uint256 public constant MAX_FEE = 2_00_000; //20%

    int24 public tickLower;
    int24 public tickUpper;
    uint24 public fee;

    uint16 public lzPoolChainId;

    uint128 public liquidity;
    uint256 private _totalSupply;

    uint256 public rewardPerTokenStored;
    uint256 public managementFees; //fees on emissions
    uint256 public lastUpdateTime;

    address public lBoxManager;

    IERC20Upgradeable public rewardToken;
    IGaugeV2 public gaugeCL;
    ILiquidBoxMinimal public box;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    /**
     *
     *  EVENTS
     *
     */

    event FeeChanged(uint24 indexed fee);
    event BoxChanged(address indexed box);
    event RewardAdded(uint256 indexed reward);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event CollectReward(address indexed user, uint256 reward);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event ClaimManagementFees(address indexed owner, address to, uint256 protocolFees);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint16 _lzPoolChainId,
        address _rewardToken,
        address _almBox,
        address _gaugeCL,
        address _lBoxManager
    ) public initializer {
        require(_rewardToken != address(0) && _gaugeCL != address(0) && _lBoxManager != address(0), "!zero address");

        __Ownable_init();
        __ReentrancyGuard_init();

        lzPoolChainId = _lzPoolChainId;
        rewardToken = IERC20Upgradeable(_rewardToken); // main reward
        // box will be deployed on selected gauge
        box = ILiquidBoxMinimal(_almBox);
        gaugeCL = IGaugeV2(_gaugeCL);
        lBoxManager = _lBoxManager;

        fee = 100_000; //10% collected from emissions
    }

    //============================== MODIFIERS ==================================

    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    //============================== SET ==================================

    function setBox(address _almBox) external onlyOwner {
        require(_almBox != address(0), "!trident");
        box = ILiquidBoxMinimal(_almBox);
        emit BoxChanged(_almBox);
    }

    /// @notice set management fee
    function setFee(uint24 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, "max fee");
        fee = newFee;
        emit FeeChanged(fee);
    }

    //============================== INTERNAL ==================================

    ///@notice deposit internal
    function _deposit(uint256 amount, address owner) internal nonReentrant updateReward(owner) {
        require(amount > 0, "deposit(Gauge): cannot stake 0");

        IERC20Upgradeable(address(box)).safeTransferFrom(owner, address(this), amount);
        _balances[owner] = _balances[owner] + amount;
        _totalSupply = _totalSupply + amount;

        _updateLiquidity(0, 0);

        emit Deposit(owner, amount);
    }

    ///@notice withdraw internal
    function _withdraw(uint256 amount, address owner) internal nonReentrant updateReward(owner) {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[owner] >= amount, "LB");
        require(_totalSupply >= amount, "supply");

        unchecked {
            _totalSupply = _totalSupply - amount;
            _balances[owner] = _balances[owner] - amount;
        }

        _updateLiquidity(0, 0);
        _collectReward(owner);

        IERC20Upgradeable(address(box)).safeTransfer(owner, amount);
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

        // Gauge ALM ticks can only be updated through rebalancing to prevent conflicts
        // while collecting rewards.
        if (_tickLower != _newTickLower) tickLower = _newTickLower;
        if (_tickUpper != _newTickUpper) tickUpper = _newTickUpper;
    }

    function _updateReward(address account) internal {
        _pullRewardFromGauge();
        if (account != address(0)) {
            rewards[account] = earnedReward(account);
            userRewardPerTokenPaid[account] = rewardPerToken();
        }
    }

    //pull reward from CL gauge
    function _pullRewardFromGauge() internal {
        unchecked {
            if (block.timestamp - lastUpdateTime == 0) return; // only once per block
        }

        if (liquidity != 0) {
            //collect reward from the CL gauge
            uint256 reward = gaugeCL.collectRewardForALM(tickLower, tickUpper);

            if (reward > 0) {
                (uint256 rewardPerTokenGrowth, uint256 managementFeesGrowth) = _getRewardsGrowth(reward);
                unchecked {
                    managementFees += managementFeesGrowth;
                    rewardPerTokenStored = rewardPerTokenStored + rewardPerTokenGrowth;
                }
            }
        }
        lastUpdateTime = block.timestamp;
    }

    function _getLatestStakedLiquidity(uint256 _liquidityPerShare) internal view returns (uint128) {
        return uint128(_totalSupply.mulDiv(_liquidityPerShare, PRECISION));
    }

    function _collectReward(address owner) internal {
        uint256 reward = rewards[owner];
        if (reward > 0) {
            rewards[owner] = 0;
            rewardToken.safeTransfer(owner, reward);
            emit CollectReward(owner, reward);
        }
    }

    function _getRewardsGrowth(uint256 reward)
        internal
        view
        returns (uint256 rewardPerTokenGrowth, uint256 managementFeesGrowth)
    {
        //fetch accrued reward
        if (reward == 0) {
            reward = gaugeCL.getRewardForALM(tickLower, tickUpper);
        }

        if (reward > 0) {
            managementFeesGrowth = reward.mulDiv(fee, ONE_HUNDRED_FEE);
            //reward - fee is avaialble for distribution to users
            unchecked {
                reward = reward - managementFeesGrowth;
            }
            rewardPerTokenGrowth = reward.mulDiv(PRECISION, _totalSupply);
        }
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
        _collectReward(msg.sender);
    }

    ///@notice transfer staked lp fee to the gaugeV2_CL
    function claimFees() external nonReentrant returns (uint256 claimed0, uint256 claimed1) {
        require(address(gaugeCL) == msg.sender, "gaugeCL");
        // fees are update before transfer of lp tokens
        if (lBoxManager != address(0) && address(box) != address(0)) {
            (claimed0, claimed1) = ILiquidBoxMinimal(lBoxManager).claimFees(address(box), address(gaugeCL));
            emit ClaimFees(msg.sender, claimed0, claimed1);
        }
    }

    function rebalanceGaugeLiquidity(int24 newtickLower, int24 newtickUpper, uint128, uint128)
        external
        nonReentrant
        updateReward(address(0))
    {
        require(address(box) == msg.sender, "!trident");
        _updateLiquidity(newtickLower, newtickUpper);
    }

    function pullGaugeLiquidity() external nonReentrant {
        require(address(box) == msg.sender, "!box");
        require(box.getPoolLiquidityPerShare() == 0, "liquidity");
        _updateLiquidity(0, 0);
    }

    function claimManagementFees(address to) external nonReentrant returns (uint256 collectedfees) {
        require(address(box) == msg.sender, "!trident");
        require(to != address(0) && to != address(this), "to");

        collectedfees = managementFees;

        if (collectedfees > 0) {
            managementFees = 0;
            rewardToken.safeTransfer(to, collectedfees);
            emit ClaimManagementFees(msg.sender, to, collectedfees);
        }
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
            (uint256 rewardPerTokenGrowth,) = _getRewardsGrowth(0);
            return rewardPerTokenStored + rewardPerTokenGrowth;
        }
        return rewardPerTokenStored;
    }

    ///@notice see earned rewards for user
    function earnedReward(address account) public view returns (uint256) {
        return
            _balances[account].mulDiv(rewardPerToken() - userRewardPerTokenPaid[account], PRECISION) + rewards[account];
    }

    ///@notice see earned rewards for user
    function earnedFees() public view returns (uint256 amount0, uint256 amount1) {
        return box.earnedFees(address(this));
    }

    ///@notice see earned management fees
    function earnedManagentFees() public view returns (uint256 totalFees) {
        (, uint256 managementFeesGrowth) = _getRewardsGrowth(0);
        totalFees = managementFeesGrowth + managementFees;
    }

    ///@notice get amounts and liquidity for the staked lp token by an account
    function getStakedAmounts(address account) external view returns (uint256, uint256, uint256) {
        return box.getSharesAmount(_balances[account]);
    }
}
