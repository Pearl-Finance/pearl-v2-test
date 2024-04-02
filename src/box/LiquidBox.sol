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
import "../interfaces/box/ILiquidBoxCallback.sol";
import "../interfaces/IGaugeV2ALM.sol";

import "../libraries/LiquidityAmounts.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {PositionFees} from "../libraries/PositionFees.sol";

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

contract LiquidBox is
    ILiquidBox,
    Initializable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint256;

    /************************************************
     *  NON UPGRADEABLE STORAGE
     ***********************************************/

    struct Fees {
        uint256 amount0;
        uint256 amount1;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    uint256 public constant PRECISION = 10 ** 36;
    uint256 public constant FEE_PRECISION = 10 ** 6;

    address public override owner; //MULTISIG address
    address public boxFactory;
    address public gauge;

    IPearlV2Pool public pool;
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;

    uint24 public poolFee;
    int24 public override tickSpacing;
    int24 public override baseUpper;
    int24 public override baseLower;
    uint24 public override fee;

    uint256 public override max0;
    uint256 public override max1;
    uint256 public override maxTotalSupply;
    uint256 public override lastTimestamp;

    bool public directDeposit;
    bool public isMinting;

    Fees public managementFees;
    Fees public usersFees;
    //1e36 precision
    Fees public feePerShare;
    //1e36 precision
    mapping(address => Fees) public feePerShareClaimed;
    mapping(address => Fees) public feesOwed;

    /************************************************
     *  EVENTS
     ***********************************************/
    event Deposit(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Withdraw(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Rebalance(
        int24 indexed tick,
        uint256 totalAmount0,
        uint256 totalAmount1,
        uint256 totalSupply
    );

    event UpdateMaxTotalSupply(uint256 indexed maxTotalSupply);
    event FeeChanged(uint24 indexed fee);
    event CollectFees(
        uint256 indexed feesToVault0,
        uint256 feesToVault1,
        uint256 feesToOwner0,
        uint256 feesToOwner1
    );
    event ClaimManagementFee(
        uint256 feesToOwner0,
        uint256 feesToOwner1,
        uint256 indexed emissionToOwner
    );
    event ClaimFees(
        address indexed from,
        address indexed to,
        uint256 feesToOwner0,
        uint256 feesToOwner1
    );
    event DirectDeposit(bool indexed isTrue);
    event OwnerChanged(address indexed owner);
    event GaugeChanged(address indexed gauge);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pool,
        address _owner,
        address _boxFactory,
        string memory _name,
        string memory _symbol
    ) public initializer {
        require(
            _pool != address(0) &&
                _owner != address(0) &&
                _boxFactory != address(0),
            "!zero address"
        );

        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        pool = IPearlV2Pool(_pool);
        token0 = IERC20Upgradeable(pool.token0());
        token1 = IERC20Upgradeable(pool.token1());
        poolFee = pool.fee();

        int24 _tickSpacing = pool.tickSpacing();
        tickSpacing = _tickSpacing;

        owner = _owner;
        boxFactory = _boxFactory;

        fee = 100_000; //10% charged on pool fee as default
        maxTotalSupply = 0; /// no cap
    }

    //============================== MODIFIERS ==================================

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyManager() {
        _checkManager();
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
        emit DirectDeposit(directDeposit);
    }

    /// @notice set owner of the contract
    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "zero addr");
        owner = _owner;
        emit OwnerChanged(_owner);
    }

    /// @notice set manager of the contract
    function setGauge(address _gauge) external onlyOwner {
        require(_gauge != address(0), "zero addr");
        gauge = _gauge;
        emit GaugeChanged(_gauge);
    }

    /// @notice set management fee
    function setFee(uint24 newFee) external onlyOwner {
        fee = newFee;
        emit FeeChanged(fee);
    }

    //============================== ACTION ==================================

    /// @inheritdoc ILiquidBox
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address to,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        nonReentrant
        onlyManager
        updateFees(to)
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        require(
            amount0Desired > 0 || amount1Desired > 0,
            "amount0Desired or amount1Desired"
        );
        require(to != address(0) && to != address(this), "to");

        // Pull in tokens from sender
        if (amount0Desired > 0) {
            amount0Desired = _safeTransferFrom(
                address(token0),
                msg.sender,
                address(this),
                amount0Desired
            );
        }

        if (amount1Desired > 0) {
            amount1Desired = _safeTransferFrom(
                address(token1),
                msg.sender,
                address(this),
                amount1Desired
            );
        }

        // Calculate amounts proportional to box's holdings
        // amount must be deducted from the total balance while
        // allocating shares since the amount is already recieved by the box
        shares = _getShares(amount0Desired, amount1Desired, true);
        require(shares > 0, "shares");

        if (directDeposit) {
            uint128 baseLiquidity = _liquidityForAmounts(
                baseLower,
                baseUpper,
                amount0Desired,
                amount1Desired
            );

            _mintLiquidity(
                baseLower,
                baseUpper,
                baseLiquidity,
                amount0Min,
                amount1Min
            );
        }

        // Mint shares to recipient
        _mint(to, shares);
        emit Deposit(msg.sender, to, shares, amount0, amount1);

        /// Check total supply cap not exceeded. A value of 0 means no base.
        require(
            maxTotalSupply == 0 || totalSupply() <= maxTotalSupply,
            "maxTotalSupply"
        );
    }

    /// @inheritdoc ILiquidBox
    function withdraw(
        uint256 shares,
        address from,
        address to,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        nonReentrant
        onlyManager
        updateFees(from)
        returns (uint256 amount0, uint256 amount1)
    {
        require(shares > 0, "shares");
        require(balanceOf(from) >= shares, "shares");
        require(to != address(0) && to != address(this), "to");

        //claim fees
        _claimFees(from, to);

        uint256 totalSupply = totalSupply();
        // Calculate token amounts proportional to unused balance
        amount0 = getBalance0().mul(shares).div(totalSupply);
        amount1 = getBalance1().mul(shares).div(totalSupply);

        {
            uint256 _shares = shares;
            (uint256 baseAmount0, uint256 baseAmount1) = _burnLiquidity(
                baseLower,
                baseUpper,
                _sharesToLiquidity(baseLower, baseUpper, _shares),
                address(this),
                amount0Min,
                amount1Min
            );

            // Sum up total amounts owed to recipient base, range and base
            amount0 = amount0.add(baseAmount0);
            amount1 = amount1.add(baseAmount1);
        }

        require(amount0 >= amount0Min, "amount0Min");
        require(amount1 >= amount1Min, "amount1Min");

        // Push tokens to recipient
        if (amount0 > 0) token0.safeTransfer(to, amount0);
        if (amount1 > 0) token1.safeTransfer(to, amount1);

        // Burn shares
        _burn(to, shares);
        emit Withdraw(from, to, shares, amount0, amount1);
    }

    /// @inheritdoc ILiquidBox
    function rebalance(
        int24 _baseLower,
        int24 _baseUpper,
        uint256 _amount0MinBurn,
        uint256 _amount1MinBurn,
        uint256 _amount0MinMint,
        uint256 _amount1MinMint
    ) external override nonReentrant onlyManager updateFees(address(0)) {
        require(
            _baseLower < _baseUpper &&
                _baseLower % tickSpacing == 0 &&
                _baseUpper % tickSpacing == 0,
            "tick"
        );

        (uint128 burnLiquidity, , , , ) = _position(baseLower, baseUpper);

        _burnLiquidity(
            baseLower,
            baseUpper,
            burnLiquidity,
            address(this),
            _amount0MinBurn,
            _amount1MinBurn
        );

        uint128 mintLiquidity = _liquidityForAmounts(
            _baseLower,
            _baseUpper,
            getBalance0(),
            getBalance1()
        );

        _mintLiquidity(
            _baseLower,
            _baseUpper,
            mintLiquidity,
            _amount0MinMint,
            _amount1MinMint
        );

        //update fee growth for Trident for new tick range
        _updateFeeGrowth(_baseLower, _baseUpper);

        baseLower = _baseLower;
        baseUpper = _baseUpper;
        lastTimestamp = block.timestamp;

        //notify liquidity update to gaugeALM
        if (gauge != address(0)) {
            IGaugeV2ALM(gauge).rebalanceGaugeLiquidity(
                _baseLower,
                _baseUpper,
                burnLiquidity,
                mintLiquidity
            );
        }

        (, int24 tick, , , , , ) = pool.slot0();
        emit Rebalance(tick, getBalance0(), getBalance1(), totalSupply());
    }

    /// @inheritdoc ILiquidBox
    function pullLiquidity(
        int24 _baseLower,
        int24 _baseUpper,
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external nonReentrant onlyManager updateFees(address(0)) {
        require(_shares <= totalSupply(), "shares");

        // When the gauge is enabled, the total shares will be removed from the pool
        if (gauge != address(0)) _shares = totalSupply();

        _burnLiquidity(
            _baseLower,
            _baseUpper,
            _sharesToLiquidity(_baseLower, _baseUpper, _shares),
            address(this),
            _amount0Min,
            _amount1Min
        );

        if (gauge != address(0)) IGaugeV2ALM(gauge).pullGaugeLiquidity();
    }

    /// @inheritdoc ILiquidBox
    function claimFees(
        address from,
        address to
    )
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
    function claimManagementFees(
        address to
    )
        external
        override
        onlyManager
        returns (
            uint256 collectedfees0,
            uint256 collectedfees1,
            uint256 emissionToOwner
        )
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

        //collect the protocol fee from emissions
        if (gauge != address(0)) {
            emissionToOwner = IGaugeV2ALM(gauge).claimManagementFees(to);
        }

        emit ClaimManagementFee(
            collectedfees0,
            collectedfees1,
            emissionToOwner
        );
    }

    /**
     * @notice Handles the callback after a successful mint operation on a Pearl V2 pool
     * @dev This function is intended to be called by the Pearl V2 pool contract only.
     * @param amount0 The amount of token0 received as a result of the mint operation
     * @param amount1 The amount of token1 received as a result of the mint operation
     *
     * @dev Reverts if the caller is not the Pearl V2 pool contract
     * @dev Transfers the received amounts of token0 and token1 to the caller's address
     */
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata
    ) external {
        require(msg.sender == address(pool), "pool");
        require(isMinting, "!lock");
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
        isMinting = false;
    }

    //============================== INTERNAL ==================================

    function _checkOwner() internal view {
        require(owner == msg.sender, "caller is not the owner");
    }

    function _checkManager() internal view {
        require(msg.sender == ILiquidBoxFactory(boxFactory).boxManager(), "BM");
    }

    /// @dev Casts uint256 to uint128 with overflow check.
    function _toUint128(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 received) {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(to);
        IERC20Upgradeable(token).safeTransferFrom(from, to, amount);
        received = IERC20Upgradeable(token).balanceOf(to) - balanceBefore;
    }

    /**
     * @notice Update fee for source and destination accounts
     * before transfering lp tokens.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        _updateFees(from);
        _updateFees(to);
    }

    function _collectFromPool(
        address account,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint256 amount0Before = token0.balanceOf(address(this));
        uint256 amount1Before = token1.balanceOf(address(this));

        (amount0, amount1) = pool.collect(
            account,
            tickLower,
            tickUpper,
            type(uint128).max, // collect maximum value
            type(uint128).max // collect maximum value
        );

        if (amount0 > 0) {
            amount0 = token0.balanceOf(address(this)) - amount0Before;
        }
        if (amount1 > 0) {
            amount1 = token1.balanceOf(address(this)) - amount1Before;
        }
    }

    /// @dev Deposits liquidity in a range on the Uniswap pool.
    function _mintLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal {
        require(!isMinting, "lock");
        if (liquidity > 0) {
            isMinting = true;
            (uint256 amount0, uint256 amount1, ) = pool.mint(
                address(this),
                address(this),
                tickLower,
                tickUpper,
                liquidity,
                ""
            );
            require(
                amount0 >= amount0Min && amount1 >= amount1Min,
                "amountMin"
            );
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
            (uint256 burned0, uint256 burned1) = pool.burn(
                tickLower,
                tickUpper,
                _toUint128(liquidity)
            );

            require(burned0 >= amount0Min && burned1 >= amount1Min, "slippage");
            (amount0, amount1) = _collectFromPool(
                account,
                tickLower,
                tickUpper
            );
        }
    }

    function _getShares(
        uint256 deposit0,
        uint256 deposit1,
        bool isDeposited
    ) internal view returns (uint256 shares) {
        uint256 totalSupply = totalSupply();
        (uint256 total0, uint256 total1, , , ) = _getTotalAmounts();

        // To support fee on transfer tokens amount is deposited before allocating the shares
        // deduct the deposited amount from the total amount if token is already transferred
        if (isDeposited) {
            total0 = total0 - deposit0;
            total1 = total1 - deposit1;
        }

        // If total supply > 0, vault can't be empty
        assert(totalSupply == 0 || total0 > 0 || total1 > 0);

        uint160 sqrtPrice = TickMath.getSqrtRatioAtTick(currentTick());
        uint256 price;
        if (sqrtPrice <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPrice) * sqrtPrice;
            price = FullMath.mulDiv(ratioX192, PRECISION, 1 << 192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1 << 64);
            price = FullMath.mulDiv(ratioX128, PRECISION, 1 << 128);
        }

        shares = deposit1.add(deposit0.mul(price).div(PRECISION));

        if (totalSupply != 0) {
            uint256 pool0PricedInToken1 = total0.mul(price).div(PRECISION);
            shares = FullMath.mulDiv(
                shares,
                totalSupply,
                pool0PricedInToken1.add(total1)
            );
        }
    }

    function _claimFees(
        address from,
        address to
    ) internal returns (uint256 collectedfees0, uint256 collectedfees1) {
        Fees storage owed = feesOwed[from];
        collectedfees0 = owed.amount0;
        collectedfees1 = owed.amount1;

        if (collectedfees0 > 0 && usersFees.amount0 >= collectedfees0) {
            owed.amount0 = 0;
            unchecked {
                usersFees.amount0 -= collectedfees0;
            }
            token0.safeTransfer(to, collectedfees0);
        }

        if (collectedfees1 > 0 && usersFees.amount1 >= collectedfees1) {
            owed.amount1 = 0;
            unchecked {
                usersFees.amount1 -= collectedfees1;
            }
            token1.safeTransfer(to, collectedfees1);
        }
        emit ClaimFees(from, to, collectedfees0, collectedfees1);
    }

    function _updateFees(address account) internal {
        // Zero burn global fee collection
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
    function _poke(
        int24 tickLower,
        int24 tickUpper
    ) internal returns (uint256 feesToPool0, uint256 feesToPool1) {
        (uint128 liquidity, , , , ) = _position(tickLower, tickUpper);
        if (liquidity > 0) {
            // Get the accumualted fee from the pool since last poke
            (feesToPool0, feesToPool1) = PositionFees.getFees(
                address(pool),
                baseLower,
                baseUpper,
                liquidity,
                usersFees.feeGrowthInside0LastX128,
                usersFees.feeGrowthInside1LastX128
            );

            if (feesToPool0 > 0 || feesToPool1 > 0) {
                // Burn zero liquidity to accumualte fees
                pool.burn(tickLower, tickUpper, 0);

                // Collect fees from the pool
                (feesToPool0, feesToPool1) = _collectFromPool(
                    address(this),
                    tickLower,
                    tickUpper
                );

                // Update collected fees
                unchecked {
                    uint256 feePerShare0;
                    uint256 feePerShare1;
                    uint256 managementFees0;
                    uint256 managementFees1;

                    (
                        feesToPool0,
                        feesToPool1,
                        feePerShare0,
                        feePerShare1,
                        managementFees0,
                        managementFees1
                    ) = _getFeeGrowth(feesToPool0, feesToPool1);

                    // Update total collected fees
                    feePerShare.amount0 += feePerShare0;
                    feePerShare.amount1 += feePerShare1;

                    managementFees.amount0 += managementFees0;
                    managementFees.amount1 += managementFees1;

                    usersFees.amount0 += feesToPool0;
                    usersFees.amount1 += feesToPool1;

                    // Update fee growth for Trident after the liquidity burn
                    _updateFeeGrowth(baseLower, baseUpper);

                    emit CollectFees(
                        feesToPool0,
                        feesToPool1,
                        managementFees0,
                        managementFees1
                    );
                }
            }
        }
    }

    // Update fee growth for the given tick ranges
    function _updateFeeGrowth(int24 tickLower, int24 tickUpper) internal {
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = _position(tickLower, tickUpper);

        usersFees.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        usersFees.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmounts()`.
    function _liquidityForAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (uint128) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount0,
                amount1
            );
    }

    /// @dev Wrapper around `IPearlV2Pool.positions()`.
    function _position(
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128, uint256, uint256, uint128, uint128) {
        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), tickLower, tickUpper)
        );
        return pool.positions(positionKey);
    }

    function _getTotalAmounts()
        internal
        view
        returns (
            uint256 total0,
            uint256 total1,
            uint256 pool0,
            uint256 pool1,
            uint128 liquidity
        )
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
    function _getPositionAmounts()
        internal
        view
        returns (uint256 amount0, uint256 amount1, uint128 liquidity)
    {
        uint128 tokensOwed0; //fee collected in token0
        uint128 tokensOwed1; //fee collected in token1
        (liquidity, , , tokensOwed0, tokensOwed1) = _position(
            baseLower,
            baseUpper
        );
        (amount0, amount1) = _amountsForLiquidity(
            baseLower,
            baseUpper,
            liquidity
        );

        // Subtract fees
        uint256 oneMinusFee = uint256(FEE_PRECISION).sub(fee);
        amount0 = amount0.add(
            uint256(tokensOwed0).mul(oneMinusFee).div(FEE_PRECISION)
        );
        amount1 = amount1.add(
            uint256(tokensOwed1).mul(oneMinusFee).div(FEE_PRECISION)
        );
    }

    /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
    function _amountsForLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal view returns (uint256, uint256) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    function _sharesToLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 shares
    ) internal view returns (uint128) {
        (uint128 totalLiquidity, , , , ) = _position(tickLower, tickUpper);
        return
            _toUint128(FullMath.mulDiv(totalLiquidity, shares, totalSupply()));
    }

    /// @dev poke a position on PearlV3 so earned fees are updated.
    function poke() external nonReentrant {
        _poke(baseLower, baseUpper);
    }

    function _claimableFeePerShare()
        internal
        view
        returns (uint256 totalFeePerShare0, uint256 totalFeePerShare1)
    {
        (uint128 totalLiquidity, , , , ) = _position(baseLower, baseUpper);

        // Get the accumulated fee from the pool since the last poke
        (uint256 feesToPool0, uint256 feesToPool1) = PositionFees.getFees(
            address(pool),
            baseLower,
            baseUpper,
            totalLiquidity,
            usersFees.feeGrowthInside0LastX128,
            usersFees.feeGrowthInside1LastX128
        );

        (, , uint256 feePerShare0, uint256 feePerShare1, , ) = _getFeeGrowth(
            feesToPool0,
            feesToPool1
        );

        //update the total fee per share
        totalFeePerShare0 = feePerShare.amount0 + feePerShare0;
        totalFeePerShare1 = feePerShare.amount1 + feePerShare1;
    }

    function _getFeeGrowth(
        uint256 feesToPool0,
        uint256 feesToPool1
    )
        internal
        view
        returns (
            uint256 userFees0,
            uint256 userFees1,
            uint256 feePerShare0,
            uint256 feePerShare1,
            uint256 managementFees0,
            uint256 managementFees1
        )
    {
        // Update the accrued protocol fees
        managementFees0 = FullMath.mulDivRoundingUp(
            feesToPool0,
            fee,
            FEE_PRECISION
        );
        managementFees1 = FullMath.mulDivRoundingUp(
            feesToPool1,
            fee,
            FEE_PRECISION
        );

        // Management fees is a percentage of feesToPool
        unchecked {
            userFees0 = feesToPool0.sub(managementFees0);
            userFees1 = feesToPool1.sub(managementFees1);
        }

        // Calculate the user fee per share based on the accrued fees
        feePerShare0 = FullMath.mulDiv(userFees0, PRECISION, totalSupply());
        feePerShare1 = FullMath.mulDiv(userFees1, PRECISION, totalSupply());
    }

    //============================== VIEW ==================================

    /// @inheritdoc ILiquidBox
    function getBalance0() public view override returns (uint256) {
        return
            token0.balanceOf(address(this)).sub(usersFees.amount0).sub(
                managementFees.amount0
            );
    }

    /// @inheritdoc ILiquidBox
    function getBalance1() public view override returns (uint256) {
        return
            token1.balanceOf(address(this)).sub(usersFees.amount1).sub(
                managementFees.amount1
            );
    }

    function getPoolParams()
        public
        view
        override
        returns (address, address, uint24)
    {
        return (address(token0), address(token1), poolFee);
    }

    /// @return tick Uniswap pool's current price tick
    function currentTick() public view returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }

    /// @inheritdoc ILiquidBox
    function getRequiredAmountsForInput(
        uint256 amount0,
        uint256 amount1
    ) public view returns (uint256, uint256) {
        int24 _lowerTick = baseLower;
        int24 _upperTick = baseUpper;
        uint128 _liquidity = _liquidityForAmounts(
            _lowerTick,
            _upperTick,
            amount0,
            amount1
        );
        return _amountsForLiquidity(_lowerTick, _upperTick, _liquidity);
    }

    /// @inheritdoc ILiquidBox
    function getSqrtTwapX96(
        uint32 twapInterval
    )
        external
        view
        override
        returns (uint160 sqrtPriceX96, uint160 sqrtPriceX96Twap)
    {
        if (twapInterval == 0) {
            /// return the current price if _twapInterval == 0
            (sqrtPriceX96, , , , , , ) = pool.slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; /// from (before)
            secondsAgos[1] = 0; /// to (now)

            (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

            int56 tickCumulativesDelta;
            unchecked {
                tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            }

            // int56 / uint32 = int24
            int24 tick = int24(tickCumulativesDelta / int32(twapInterval));
            // Always round to negative infinity
            /*
        int doesn't round down when it is negative

        int56 a = -3
        -3 / 10 = -3.3333... so round down to -4
        but we get
        a / 10 = -3

        so if tickCumulativeDelta < 0 and division has remainder, then round
        down
        */
            if (
                tickCumulativesDelta < 0 &&
                (tickCumulativesDelta % int32(twapInterval) != 0)
            ) {
                unchecked {
                    tick--;
                }
            }

            /// tick(imprecise as it's an integer) to price
            sqrtPriceX96Twap = TickMath.getSqrtRatioAtTick(tick);
        }
    }

    /// @inheritdoc ILiquidBox
    function getPoolLiquidityPerShare()
        public
        view
        override
        returns (uint256 liquidityPerShare)
    {
        (uint128 totalLiquidity, , , , ) = _position(baseLower, baseUpper);

        if (totalSupply() == 0) return 0;

        liquidityPerShare = FullMath.mulDiv(
            totalLiquidity,
            PRECISION,
            totalSupply()
        );
    }

    /// @inheritdoc ILiquidBox
    function getSharesAmount(
        uint256 shares
    )
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

            (
                uint128 totalLiquidity,
                ,
                ,
                uint256 tokensOwed0,
                uint256 tokensOwed1
            ) = _position(baseLower, baseUpper);

            liquidity = FullMath.mulDiv(totalLiquidity, shares, totalSupply);

            (
                uint256 liquidityAmount0,
                uint256 liquidityAmount1
            ) = _amountsForLiquidity(baseLower, baseUpper, uint128(liquidity));

            // Calculate the tokens owed after zero burn, based on the given shares.
            tokensOwed0 = tokensOwed0.mul(shares).div(totalSupply);
            tokensOwed1 = tokensOwed1.mul(shares).div(totalSupply);

            // Subtract fees
            uint256 oneMinusFee = uint256(FEE_PRECISION).sub(fee);
            amount0 = amount0.add(liquidityAmount0).add(
                uint256(tokensOwed0).mul(oneMinusFee).div(FEE_PRECISION)
            );
            amount1 = amount1.add(liquidityAmount1).add(
                uint256(tokensOwed1).mul(oneMinusFee).div(FEE_PRECISION)
            );
        }
    }

    /// @inheritdoc ILiquidBox
    function getTotalAmounts()
        external
        view
        override
        returns (
            uint256 total0,
            uint256 total1,
            uint256 pool0,
            uint256 pool1,
            uint128 liquidity
        )
    {
        return _getTotalAmounts();
    }

    /// @inheritdoc ILiquidBox
    function getManagementFees()
        external
        view
        override
        returns (
            uint256 claimable0,
            uint256 claimable1,
            uint256 claimableEmission
        )
    {
        claimable0 = managementFees.amount0;
        claimable1 = managementFees.amount1;
        // Collect the protocol fee from emissions.
        if (gauge != address(0)) {
            claimableEmission = IGaugeV2ALM(gauge).earnedManagentFees();
        }
    }

    ///@notice see earned rewards for user
    function earnedFees(
        address account
    ) public view returns (uint256 amount0, uint256 amount1) {
        Fees memory userFeesPaidPerToken = feePerShareClaimed[account];

        (
            uint256 totalFeePerShare0,
            uint256 totalFeePerShare1
        ) = _claimableFeePerShare();

        // Check if there is any difference that needs to be accrued.
        uint256 _delta0 = totalFeePerShare0.sub(userFeesPaidPerToken.amount0);
        uint256 _delta1 = totalFeePerShare1.sub(userFeesPaidPerToken.amount1);

        amount0 = FullMath.mulDiv(balanceOf(account), _delta0, PRECISION).add(
            feesOwed[account].amount0
        );

        amount1 = FullMath.mulDiv(balanceOf(account), _delta1, PRECISION).add(
            feesOwed[account].amount1
        );
    }
}
