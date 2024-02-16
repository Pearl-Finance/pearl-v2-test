// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/dex/IPearlV2Pool.sol";
import "../interfaces/box/ILiquidBox.sol";
import "../interfaces/box/ILiquidBoxFactory.sol";
import "../interfaces/IGaugeV2ALM.sol";

import "../libraries/LiquidityAmounts.sol";
import {TickMath} from "../libraries/TickMath.sol";

/**
 * @title Trident Active Liquidity Management for PearlV3 Concentrated Liquidity Pool
 * @author Maverick
 * @notice This contract manages a user's liquidity position with active liquidity management strategies.
 * Users can deposit in various strategies: For instance, Narrow Range and Wide Range, optimizing liquidity provision.
 * Narrow Range strategy focuses on tightly concentrated liquidity within a specific price range.
 * Wide Range strategy spans a broader price range, accommodating more volatile market conditions.
 * This contract facilitates liquidity management for targeted and adaptive provision based on market dynamics.
 * For detailed function descriptions and strategies, refer to protocol documentaion.
 */

contract LiquidBox is ILiquidBox, Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint256;

    /**
     *
     *  NON UPGRADEABLE STORAGE
     *
     */

    struct Fees {
        uint256 amount0;
        uint256 amount1;
    }

    address public override owner; //MULTISIG address
    address public boxFactory;
    address public gauge;

    IPearlV2Pool public pool;
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;

    int24 public override tickSpacing;
    int24 public override baseUpper;
    int24 public override baseLower;
    uint24 public override fee;

    uint256 public override max0;
    uint256 public override max1;
    uint256 public override maxTotalSupply;
    uint256 public override lastTimestamp;
    uint256 public constant PRECISION = 1e36;

    bool public directDeposit;

    Fees public managementFees;
    Fees public usersFees;
    //1e36 precision
    Fees public feePerShare;
    //1e36 precision
    mapping(address => Fees) public feePerShareClaimed;
    mapping(address => Fees) public feesOwed;

    /**
     *
     *  EVENTS
     *
     */
    event Deposit(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);

    event Withdraw(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);

    event Rebalance(int24 tick, uint256 totalAmount0, uint256 totalAmount1, uint256 totalSupply);

    event UpdateMaxTotalSupply(uint256 maxTotalSupply);

    event SetFee(uint24 fee);

    event CollectFees(uint256 feesToVault0, uint256 feesToVault1, uint256 feesToOwner0, uint256 feesToOwner1);
    event ClaimManagementFee(uint256 feesToOwner0, uint256 feesToOwner1);
    event ClaimFee(uint256 feesToOwner0, uint256 feesToOwner1);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _pool, address _owner, address _boxFactory, string memory _name, string memory _symbol)
        public
        initializer
    {
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        pool = IPearlV2Pool(_pool);
        token0 = IERC20Upgradeable(pool.token0());
        token1 = IERC20Upgradeable(pool.token1());

        int24 _tickSpacing = pool.tickSpacing();
        tickSpacing = _tickSpacing;

        owner = _owner;
        boxFactory = _boxFactory;

        fee = 100000; //10% charged on pool fee as default
        maxTotalSupply = 0;
        /// no cap
    }

    //============================== MODIFIERS ==================================

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == ILiquidBoxFactory(boxFactory).boxManager(), "BM");
        _;
    }

    modifier updateFees(address account) {
        _updateFees(account);
        _;
    }

    //============================== SET_FUNCTIONS ==================================

    /**
     * @notice Used to change deposit cap for a guarded launch or to ensure
     * vault doesn't grow too large relative to the pool. Cap is on total
     * supply rather than amounts of token0 and token1 as those amounts
     * fluctuate naturally over time.
     */
    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyOwner {
        maxTotalSupply = _maxTotalSupply;
        emit UpdateMaxTotalSupply(_maxTotalSupply);
    }

    /// @notice Toggle Direct Deposit
    function toggleDirectDeposit() external onlyOwner {
        require(baseLower != 0 || baseUpper != 0, "tick");
        directDeposit = !directDeposit;
    }

    /// @notice set owner of the contract
    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    /// @notice set manager of the contract
    function setGauge(address _gauge) external onlyOwner {
        gauge = _gauge;
    }

    /// @notice set management fee
    function setFee(uint24 newFee) external onlyOwner {
        fee = newFee;
        emit SetFee(fee);
    }

    //============================== ACTION ==================================

    /// @inheritdoc ILiquidBox
    function deposit(uint256 amount0Desired, uint256 amount1Desired, address to, uint256 amount0Min, uint256 amount1Min)
        external
        override
        onlyManager
        nonReentrant
        updateFees(to)
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        require(amount0Desired > 0 || amount1Desired > 0, "amount0Desired or amount1Desired");
        require(to != address(0) && to != address(this), "to");

        // Calculate amounts proportional to vault's holdings
        shares = _getShares(amount0Desired, amount1Desired);
        require(shares > 0, "shares");

        // Pull in tokens from sender
        if (amount0Desired > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0Desired);
        }
        if (amount1Desired > 0) {
            token1.safeTransferFrom(msg.sender, address(this), amount1Desired);
        }

        if (directDeposit) {
            uint128 baseLiquidity = _liquidityForAmounts(baseLower, baseUpper, getBalance0(), getBalance1());

            _mintLiquidity(baseLower, baseUpper, baseLiquidity, amount0Min, amount1Min);
        }

        // Mint shares to recipient
        _mint(to, shares);
        emit Deposit(msg.sender, to, shares, amount0, amount1);

        /// Check total supply cap not exceeded. A value of 0 means no base.
        require(maxTotalSupply == 0 || totalSupply() <= maxTotalSupply, "maxTotalSupply");
    }

    /// @inheritdoc ILiquidBox
    function withdraw(uint256 shares, address to, uint256 amount0Min, uint256 amount1Min)
        external
        override
        onlyManager
        nonReentrant
        updateFees(to)
        returns (uint256 amount0, uint256 amount1)
    {
        require(shares > 0, "shares");
        require(balanceOf(to) >= shares, "shares");
        require(to != address(0) && to != address(this), "to");

        //claim fees
        _claimFees(msg.sender, to);

        uint256 totalSupply = totalSupply();
        // Calculate token amounts proportional to unused balance
        amount0 = getBalance0().mul(shares).div(totalSupply);
        amount1 = getBalance1().mul(shares).div(totalSupply);

        (uint256 baseAmount0, uint256 baseAmount1) = _burnLiquidity(
            baseLower,
            baseUpper,
            _sharesToLiquidity(baseLower, baseUpper, shares),
            address(this),
            amount0Min,
            amount1Min
        );

        // Sum up total amounts owed to recipient base, range and base
        amount0 = amount0.add(baseAmount0);
        amount1 = amount1.add(baseAmount1);

        require(amount0 >= amount0Min, "amount0Min");
        require(amount1 >= amount1Min, "amount1Min");

        // Push tokens to recipient
        if (amount0 > 0) token0.safeTransfer(to, amount0);
        if (amount1 > 0) token1.safeTransfer(to, amount1);

        // Burn shares
        _burn(to, shares);
        emit Withdraw(msg.sender, to, shares, amount0, amount1);
    }

    /// @inheritdoc ILiquidBox
    function addLiquidity(
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external override onlyManager updateFees(address(0)) {
        uint128 liquidity = _liquidityForAmounts(_tickLower, _tickUpper, _amount0, _amount1);

        _mintLiquidity(_tickLower, _tickUpper, liquidity, _amount0Min, _amount1Min);
    }

    /// @inheritdoc ILiquidBox
    function rebalance(
        int24 _baseLower,
        int24 _baseUpper,
        uint256 _amount0MinBurn,
        uint256 _amount1MinBurn,
        uint256 _amount0MinMint,
        uint256 _amount1MinMint
    ) external override onlyManager nonReentrant updateFees(address(0)) {
        require(_baseLower < _baseUpper && _baseLower % tickSpacing == 0 && _baseUpper % tickSpacing == 0, "tick");

        (uint128 burnLiquidity,,,,) = _position(baseLower, baseUpper);

        _burnLiquidity(baseLower, baseUpper, burnLiquidity, address(this), _amount0MinBurn, _amount1MinBurn);

        uint128 mintLiquidity = _liquidityForAmounts(_baseLower, _baseUpper, getBalance0(), getBalance1());

        _mintLiquidity(_baseLower, _baseUpper, mintLiquidity, _amount0MinMint, _amount1MinMint);

        baseLower = _baseLower;
        baseUpper = _baseUpper;
        lastTimestamp = block.timestamp;

        //notify liquidity update to gaugeALM
        if (gauge != address(0)) {
            IGaugeV2ALM(gauge).rebalanceGaugeLiquidity(_baseLower, _baseUpper, burnLiquidity, mintLiquidity);
        }

        (, int24 tick,,,,,) = pool.slot0();
        emit Rebalance(tick, getBalance0(), getBalance1(), totalSupply());
    }

    /// @inheritdoc ILiquidBox
    function pullLiquidity(
        int24 _baseLower,
        int24 _baseUpper,
        uint128 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyManager nonReentrant updateFees(address(0)) {
        require(_shares <= totalSupply(), "shares");
        _burnLiquidity(
            _baseLower,
            _baseUpper,
            _sharesToLiquidity(_baseLower, _baseUpper, _shares),
            address(this),
            _amount0Min,
            _amount1Min
        );

        if (gauge != address(0)) {
            IGaugeV2ALM(gauge).pullGaugeLiquidity();
        }
    }

    /// @inheritdoc ILiquidBox
    function claimFees(address from, address to)
        external
        nonReentrant
        onlyManager
        updateFees(from)
        returns (uint256 collectedfees0, uint256 collectedfees1)
    {
        require(to != address(0) && to != address(this), "to");
        return _claimFees(from, to);
    }

    /// @inheritdoc ILiquidBox
    function claimManagementFees(address to)
        external
        override
        onlyManager
        returns (uint256 collectedfees0, uint256 collectedfees1)
    {
        require(to != address(0) && to != address(this), "to");
        collectedfees0 = managementFees.amount0;
        collectedfees1 = managementFees.amount0;

        if (collectedfees0 > 0) {
            managementFees.amount0 = 0;
            token0.safeTransfer(to, collectedfees0);
        }

        if (collectedfees1 > 0) {
            managementFees.amount1 = 0;
            token1.safeTransfer(to, collectedfees1);
        }

        emit ClaimManagementFee(collectedfees0, collectedfees1);
    }

    /// @dev Callback for Pearl V2 pool.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        require(msg.sender == address(pool), "pool");
        if (amount0Delta > 0) {
            require(uint256(amount0Delta) <= getBalance0(), "balance0");
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0 && uint256(amount1Delta) <= getBalance1()) {
            require(uint256(amount1Delta) <= getBalance1(), "balance1");
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice Handles the callback after a successful mint operation on a Pearl V2 pool
     * @dev This function is intended to be called by the Pearl V2 pool contract only.
     * @param amount0 The amount of token0 received as a result of the mint operation
     * @param amount1 The amount of token1 received as a result of the mint operation
     * @param data Additional data that may be included with the callback
     * @dev Reverts if the caller is not the Pearl V2 pool contract
     * @dev Transfers the received amounts of token0 and token1 to the caller's address
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == address(pool), "pool");
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
    }

    //============================== INTERNAL ==================================

    /// @dev Casts uint256 to uint128 with overflow check.
    function _toUint128(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    /**
     * @notice Update fee for source and destination accounts
     * before transfering lp tokens.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        _updateFees(from);
        _updateFees(to);
    }

    /// @dev Deposits liquidity in a range on the Uniswap pool.
    function _mintLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 amount0Min, uint256 amount1Min)
        internal
    {
        if (liquidity > 0) {
            (uint256 amount0, uint256 amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, "");
            require(amount0 >= amount0Min && amount1 >= amount1Min, "amountMin");
        }
    }

    /// @dev Withdraws share of liquidity in a range from Uniswap pool.
    function _burnLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address account,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidity > 0) {
            (uint256 burned0, uint256 burned1) = pool.burn(tickLower, tickUpper, _toUint128(liquidity));
            require(burned0 >= amount0Min && burned1 >= amount1Min, "slippage");
            (amount0, amount1) = pool.collect(account, tickLower, tickUpper, type(uint128).max, type(uint128).max);
        }
    }

    function _getShares(uint256 deposit0, uint256 deposit1) internal view returns (uint256 shares) {
        uint256 totalSupply = totalSupply();
        (uint256 total0, uint256 total1,,,) = _getTotalAmounts();

        // If total supply > 0, vault can't be empty
        assert(totalSupply == 0 || total0 > 0 || total1 > 0);

        uint160 sqrtPrice = TickMath.getSqrtRatioAtTick(currentTick());
        uint256 price = FullMath.mulDiv(uint256(sqrtPrice).mul(uint256(sqrtPrice)), PRECISION, 2 ** (96 * 2));

        shares = deposit1.add(deposit0.mul(price).div(PRECISION));

        if (totalSupply != 0) {
            uint256 pool0PricedInToken1 = total0.mul(price).div(PRECISION);
            shares = FullMath.mulDiv(shares, totalSupply, pool0PricedInToken1.add(total1));
        }
    }

    function _claimFees(address from, address to) internal returns (uint256 collectedfees0, uint256 collectedfees1) {
        Fees storage owed = feesOwed[from];
        collectedfees0 = owed.amount0;
        collectedfees1 = owed.amount1;

        if (collectedfees0 > 0 && usersFees.amount0 >= collectedfees0) {
            owed.amount0 = 0;
            usersFees.amount0 -= collectedfees0;
            token0.safeTransfer(to, collectedfees0);
        }

        if (collectedfees1 > 0 && usersFees.amount1 >= collectedfees1) {
            owed.amount1 = 0;
            usersFees.amount1 -= collectedfees1;
            token1.safeTransfer(to, collectedfees1);
        }
        emit ClaimFee(collectedfees0, collectedfees1);
    }

    function _updateFees(address account) internal {
        //Zero burn global fee collection
        _poke(baseLower, baseUpper);
        if (balanceOf(account) > 0) {
            Fees storage owed = feesOwed[account];
            (owed.amount0, owed.amount1) = earnedFees(account);
        }
        feePerShareClaimed[account].amount0 = feePerShare.amount0;
        feePerShareClaimed[account].amount1 = feePerShare.amount1;
    }

    /// @dev Do zero-burns to poke a position on Uniswap so earned fees are
    ///updated. Should be called if total amounts needs to include up-to-date fees.
    function _poke(int24 tickLower, int24 tickUpper) internal returns (uint256 feesToPool0, uint256 feesToPool1) {
        (uint128 liquidity,,,,) = _position(tickLower, tickUpper);
        if (liquidity > 0) {
            pool.burn(tickLower, tickUpper, 0);
            (feesToPool0, feesToPool1) =
                pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

            unchecked {
                if (feesToPool0 > 0 || feesToPool1 > 0) {
                    // Update accrued protocol fees
                    uint256 fees0 = FullMath.mulDivRoundingUp(feesToPool0, fee, 1e6);
                    uint256 fees1 = FullMath.mulDivRoundingUp(feesToPool1, fee, 1e6);

                    managementFees.amount0 = managementFees.amount0.add(fees0);
                    managementFees.amount1 = managementFees.amount1.add(fees1);

                    feesToPool0 = feesToPool0.sub(fees0);
                    feesToPool1 = feesToPool1.sub(fees1);

                    //Update total collected fees in box
                    feePerShare.amount0 += FullMath.mulDiv(feesToPool0, PRECISION, totalSupply());

                    feePerShare.amount1 += FullMath.mulDiv(feesToPool1, PRECISION, totalSupply());

                    usersFees.amount0 += feesToPool0;
                    usersFees.amount1 += feesToPool1;
                    emit CollectFees(feesToPool0, feesToPool1, fees0, fees1);
                }
            }
        }
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmounts()`.
    function _liquidityForAmounts(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        internal
        view
        returns (uint128)
    {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0,
            amount1
        );
    }

    /// @dev Wrapper around `IPearlV2Pool.positions()`.
    function _position(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint128, uint256, uint256, uint128, uint128)
    {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        return pool.positions(positionKey);
    }

    function _getTotalAmounts()
        internal
        view
        returns (uint256 total0, uint256 total1, uint256 pool0, uint256 pool1, uint128 liquidity)
    {
        (pool0, pool1, liquidity) = _getPositionAmounts();
        // Sum up balance base, range and base
        total0 = getBalance0().add(pool0);
        total1 = getBalance1().add(pool1);
    }

    /**
     * @notice Amounts of token0 and token1 held in vault's position. Includes
     * owed fees but excludes the proportion of fees that will be paid to the
     * protocol. Doesn't include fees accrued since last poke.
     */
    function _getPositionAmounts() internal view returns (uint256 amount0, uint256 amount1, uint128 liquidity) {
        uint128 tokensOwed0; //fee collected in token0
        uint128 tokensOwed1; //fee collected in token1
        (liquidity,,, tokensOwed0, tokensOwed1) = _position(baseLower, baseUpper);
        (amount0, amount1) = _amountsForLiquidity(baseLower, baseUpper, liquidity);

        // Subtract fees
        uint256 oneMinusFee = uint256(1e6).sub(fee);
        amount0 = amount0.add(uint256(tokensOwed0).mul(oneMinusFee).div(1e6));
        amount1 = amount1.add(uint256(tokensOwed1).mul(oneMinusFee).div(1e6));
    }

    /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
    function _amountsForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        view
        returns (uint256, uint256)
    {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }

    function _sharesToLiquidity(int24 tickLower, int24 tickUpper, uint256 shares) internal view returns (uint128) {
        (uint128 totalLiquidity,,,,) = _position(tickLower, tickUpper);
        return _toUint128(FullMath.mulDiv(totalLiquidity, shares, totalSupply()));
    }

    /// @dev poke a position on PearlV3 so earned fees are updated.
    function poke() external {
        _poke(baseLower, baseUpper);
    }

    //============================== VIEW ==================================

    /// @inheritdoc ILiquidBox
    function getBalance0() public view override returns (uint256) {
        return token0.balanceOf(address(this)).sub(usersFees.amount0).sub(managementFees.amount0);
    }

    /// @inheritdoc ILiquidBox
    function getBalance1() public view override returns (uint256) {
        return token1.balanceOf(address(this)).sub(usersFees.amount1).sub(managementFees.amount1);
    }

    /// @return tick Uniswap pool's current price tick
    function currentTick() public view returns (int24 tick) {
        (, tick,,,,,) = pool.slot0();
    }

    /// @inheritdoc ILiquidBox
    function getSqrtTwapX96(uint32 twapInterval) external view override returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            /// return the current price if _twapInterval == 0
            (sqrtPriceX96,,,,,,) = pool.slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval;
            /// from (before)
            secondsAgos[1] = 0;
            /// to (now)

            (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);

            /// tick(imprecise as it's an integer) to price
            sqrtPriceX96 =
                TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int32(twapInterval)));
        }
    }

    /// @inheritdoc ILiquidBox
    function getPoolLiquidityPerShare() public view override returns (uint256 liquidityPerShare) {
        (uint128 totalLiquidity,,,,) = _position(baseLower, baseUpper);

        if (totalSupply() == 0) return 0;

        liquidityPerShare = FullMath.mulDiv(totalLiquidity, PRECISION, totalSupply());
    }

    /// @inheritdoc ILiquidBox
    function getSharesAmount(uint256 shares)
        public
        view
        override
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        require(shares <= totalSupply(), "supply");
        if (shares > 0) {
            uint256 totalSupply = totalSupply();

            // Calculate token amounts proportional to unused balance
            amount0 = FullMath.mulDiv(getBalance0(), shares, totalSupply);
            amount1 = FullMath.mulDiv(getBalance1(), shares, totalSupply);

            (uint128 totalLiquidity,,, uint256 tokensOwed0, uint256 tokensOwed1) = _position(baseLower, baseUpper);

            liquidity = FullMath.mulDiv(totalLiquidity, shares, totalSupply);

            (uint256 liquidityAmount0, uint256 liquidityAmount1) =
                _amountsForLiquidity(baseLower, baseUpper, uint128(liquidity));

            //Calculate tokens owed while zero burn for the given shares
            tokensOwed0 = tokensOwed0.mul(shares).div(totalSupply);
            tokensOwed1 = tokensOwed1.mul(shares).div(totalSupply);

            // Subtract fees
            uint256 oneMinusFee = uint256(1e6).sub(fee);
            amount0 = amount0.add(liquidityAmount0).add(uint256(tokensOwed0).mul(oneMinusFee).div(1e6));
            amount1 = amount1.add(liquidityAmount1).add(uint256(tokensOwed1).mul(oneMinusFee).div(1e6));
        }
    }

    /// @inheritdoc ILiquidBox
    function getTotalAmounts()
        external
        view
        override
        returns (uint256 total0, uint256 total1, uint256 pool0, uint256 pool1, uint128 liquidity)
    {
        return _getTotalAmounts();
    }

    ///@notice see earned rewards for user
    function earnedFees(address account) public view returns (uint256 amount0, uint256 amount1) {
        Fees memory userFeesPaidPerToken = feePerShareClaimed[account];
        // see if there is any difference that need to be accrued
        uint256 _delta0 = feePerShare.amount0.sub(userFeesPaidPerToken.amount0);
        uint256 _delta1 = feePerShare.amount1.sub(userFeesPaidPerToken.amount1);

        amount0 = FullMath.mulDiv(balanceOf(account), _delta0, PRECISION).add(feesOwed[account].amount0);

        amount1 = FullMath.mulDiv(balanceOf(account), _delta1, PRECISION).add(feesOwed[account].amount1);
    }
}
