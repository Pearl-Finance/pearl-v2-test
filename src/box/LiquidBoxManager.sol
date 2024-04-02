// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/contracts/utils/math/SafeMath.sol";
import "../libraries/FullMath.sol";

import "../interfaces/box/ILiquidBox.sol";
import "../interfaces/box/ILiquidBoxFactory.sol";
import "../interfaces/box/ILiquidBoxManager.sol";
import "../interfaces/periphery/external/IWETH9.sol";

/**
 * @title Trident Active Liquidity Management Manager Contract
 * @author Maverick
 * @notice This manager contract oversees multiple Active Liquidity Management Contracts.
 * It facilitates depositing, withdrawing, and rebalancing of liquidity across these all box contracts.
 * Users can efficiently manage liquidity provision strategies through this manager, optimizing resources
 * across various PearlV3 Concentrated Liquidity Pools.
 * The manager enables seamless coordination for depositing assets into, withdrawing assets from,
 * and rebalancing liquidity positions within the deployed Active Liquidity Management Contracts.
 * For detailed function descriptions and interaction guidelines, refer to protocol documentaion.
 */

contract LiquidBoxManager is
    ILiquidBoxManager,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint256;

    /************************************************
     *  NON UPGRADEABLE STORAGE
     ***********************************************/

    uint256 internal constant DECIMAL_PREICISION = 10 ** 18;
    uint256 internal constant SQRT_PRICE_DENOMINATOR = 2 ** (96 * 2);
    uint256 internal constant PRICE_PRECISION = 1_00;

    address public factory;
    address public manager;
    address public WETH9;
    address public feeRecipient;

    bool isTwapCheck;
    uint32 public twapInterval;
    uint256 public priceThreshold;

    mapping(address => BoxParams) public boxParams;

    /************************************************
     *  EVENTS
     ***********************************************/

    event BoxParamAdded(address indexed box, uint8 version);

    event Deposit(
        address indexed box,
        address to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );
    event Withdraw(
        address indexed box,
        address to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    event Rebalance(
        address indexed box,
        int24 baseLower,
        int24 baseUpper,
        uint256 amount0Min,
        uint256 amount1Min
    );

    event ClaimFees(
        address indexed box,
        address to,
        uint256 feesToOwner0,
        uint256 feesToOwner1
    );

    event ClaimManagementFee(
        address indexed box,
        address to,
        uint256 feesToOwner0,
        uint256 feesToOwner1,
        uint256 collectedFeeOnEmission
    );

    event TwapToggled();
    event FactoryChanged(address indexed factory);
    event ManagerChanged(address indexed manager);
    event FeeRecipientChanged(address indexed recipient);
    event PriceThresholdUpdated(uint256 threshold);
    event TwapIntervalUpdated(uint32 twapInterval);
    event TwapOverrideUpdated(
        address indexed box,
        bool twapOverride,
        uint32 twapInterval
    );
    event BoxPriceThresholdUpdated(address indexed box, uint256 priceThreshold);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _intialOwner,
        address _feeRecipient,
        address _factory,
        address _weth9
    ) public initializer {
        require(
            _intialOwner != address(0) &&
                _feeRecipient != address(0) &&
                _factory != address(0) &&
                _weth9 != address(0),
            "!zero address"
        );

        __Ownable_init();
        __ReentrancyGuard_init();
        _transferOwnership(_intialOwner);

        factory = _factory;
        manager = _intialOwner;
        feeRecipient = _feeRecipient;
        WETH9 = _weth9;

        twapInterval = 1 hours;
        priceThreshold = 1_00;
    }

    modifier onlyManager() {
        _checkManager();
        _;
    }

    modifier onlyAllowed() {
        _onlyAllowed();
        _;
    }

    modifier isBoxAdded(address box) {
        BoxParams storage b = boxParams[box];
        require(b.version != 0, "!box");
        _;
    }

    /// @inheritdoc ILiquidBoxManager
    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
        emit FactoryChanged(_factory);
    }

    /// @notice set manager to manage deposited funds
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerChanged(_manager);
    }

    /// @notice Add the trident box
    function addBoxParam(address box, uint8 version) external onlyAllowed {
        require(box != address(0), "!box");
        BoxParams storage b = boxParams[box];
        require(b.version == 0, "already added");
        require(version > 0, "version < 1");
        b.version = version;
        emit BoxParamAdded(box, version);
    }

    /// @notice Twap Toggle
    function toggleTwap() external onlyOwner {
        isTwapCheck = !isTwapCheck;
        emit TwapToggled();
    }

    /// @param _priceThreshold Price Threshold
    function setPriceThreshold(uint256 _priceThreshold) external onlyOwner {
        priceThreshold = _priceThreshold;
        emit PriceThresholdUpdated(_priceThreshold);
    }

    /// @param _twapInterval Twap interval
    function setTwapInterval(uint32 _twapInterval) external onlyOwner {
        twapInterval = _twapInterval;
        emit TwapIntervalUpdated(_twapInterval);
    }

    function setTwapOverride(
        address box,
        bool twapOverride,
        uint32 _twapInterval
    ) external onlyAllowed isBoxAdded(box) {
        BoxParams storage b = boxParams[box];
        b.twapOverride = twapOverride;
        b.twapInterval = _twapInterval;
        emit TwapOverrideUpdated(box, twapOverride, _twapInterval);
    }

    /// @param box Box Address
    /// @param _priceThreshold Price Threshold
    function setBoxPriceThreshold(
        address box,
        uint256 _priceThreshold
    ) external onlyOwner isBoxAdded(box) {
        BoxParams storage b = boxParams[box];
        b.priceThreshold = _priceThreshold;
        emit BoxPriceThresholdUpdated(box, _priceThreshold);
    }

    /// @param _feeRecipient fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(_feeRecipient);
    }

    // =================== Internal  ===================

    function _checkManager() internal view {
        require(msg.sender == manager, "manager");
    }

    function _onlyAllowed() internal view {
        require(msg.sender == manager || msg.sender == owner(), "!allowed");
    }

    /// @notice retreives the box address based on tokens and fee
    function _getBox(
        address token0,
        address token1,
        uint24 fee
    ) internal view returns (address) {
        return ILiquidBoxFactory(factory).getBox(token0, token1, fee);
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "failed inner call");
    }

    // =================== MAIN ===================

    /// @inheritdoc ILiquidBoxManager
    function deposit(
        address box,
        uint256 deposit0,
        uint256 deposit1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable override nonReentrant returns (uint256 shares) {
        require(deposit0 > 0 || deposit1 > 0, "deposit0 or deposit1");

        // re-calcualte the amounts for a given tick range using the input amounts
        (deposit0, deposit1) = getRequiredAmountsForInput(
            box,
            deposit0,
            deposit1
        );

        BoxParams memory b = boxParams[box];
        if (isTwapCheck || b.twapOverride) {
            checkPriceChange(
                box,
                (b.twapOverride ? b.twapInterval : twapInterval),
                (b.twapOverride ? b.priceThreshold : priceThreshold)
            );
        }

        if (deposit0 > 0) {
            deposit0 = _safeTransferFrom(
                address(ILiquidBox(box).token0()),
                msg.sender,
                address(this),
                deposit0
            );
            ILiquidBox(box).token0().safeIncreaseAllowance(box, deposit0);
        }

        if (deposit1 > 0) {
            deposit1 = _safeTransferFrom(
                address(ILiquidBox(box).token1()),
                msg.sender,
                address(this),
                deposit1
            );
            ILiquidBox(box).token1().safeIncreaseAllowance(box, deposit1);
        }

        (shares, , ) = ILiquidBox(box).deposit(
            deposit0,
            deposit1,
            msg.sender,
            amount0Min,
            amount1Min
        );

        // return the unutilized eth amount to the payer
        if (address(this).balance > 0) {
            _sendValue(payable(msg.sender), address(this).balance);
        }

        emit Deposit(box, msg.sender, deposit0, deposit1, shares);
    }

    /// @inheritdoc ILiquidBoxManager
    function withdraw(
        address box,
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = ILiquidBox(box).withdraw(
            shares,
            msg.sender,
            msg.sender,
            amount0Min,
            amount1Min
        );
        emit Withdraw(box, msg.sender, shares, amount0, amount1);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 received) {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(to);
        if (token == WETH9 && address(this).balance >= amount) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: amount}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(to, amount);
        } else {
            IERC20Upgradeable(token).safeTransferFrom(from, to, amount);
        }
        received = IERC20Upgradeable(token).balanceOf(to) - balanceBefore;
    }

    /// @inheritdoc ILiquidBoxManager
    function rebalance(
        address box,
        int24 baseLower,
        int24 baseUpper,
        uint256 amount0MinBurn,
        uint256 amount1MinBurn,
        uint256 amount0MinMint,
        uint256 amount1MinMint
    ) external override onlyAllowed nonReentrant {
        ILiquidBox(box).rebalance(
            baseLower,
            baseUpper,
            amount0MinBurn,
            amount1MinBurn,
            amount0MinMint,
            amount1MinMint
        );
        emit Rebalance(
            box,
            baseLower,
            baseUpper,
            amount0MinMint,
            amount1MinMint
        );
    }

    /// @inheritdoc ILiquidBoxManager
    function pullLiquidity(
        address box,
        int24 baseLower,
        int24 baseUpper,
        uint128 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override onlyAllowed nonReentrant {
        ILiquidBox(box).pullLiquidity(
            baseLower,
            baseUpper,
            shares,
            amount0Min,
            amount1Min
        );
    }

    /// @inheritdoc ILiquidBoxManager
    function claimManagementFees(
        address box
    )
        external
        override
        onlyAllowed
        nonReentrant
        returns (
            uint256 collectedfees0,
            uint256 collectedfees1,
            uint256 collectedEmission
        )
    {
        require(box != address(0), "box");
        address _feeRecipient = feeRecipient;
        (collectedfees0, collectedfees1, collectedEmission) = ILiquidBox(box)
            .claimManagementFees(_feeRecipient);
        emit ClaimManagementFee(
            box,
            _feeRecipient,
            collectedfees0,
            collectedfees1,
            collectedEmission
        );
    }

    /// @inheritdoc ILiquidBoxManager
    function claimFees(
        address box,
        address to
    )
        external
        override
        nonReentrant
        returns (uint256 collectedfees0, uint256 collectedfees1)
    {
        require(box != address(0), "box");
        require(to != address(0) && to != address(this), "to");
        (
            //safe as msg.sender is claiming the fee and traferring to the specified address
            collectedfees0,
            collectedfees1
        ) = ILiquidBox(box).claimFees(msg.sender, to);
        emit ClaimFees(box, to, collectedfees0, collectedfees1);
    }

    // =================== VIEW ===================

    /// @notice Check if the price change overflows or not based on given twap and threshold in the box
    /// @param box box Address
    /// @param _twapInterval Time intervals
    /// @param _priceThreshold Price Threshold
    /// @return price Current price
    function checkPriceChange(
        address box,
        uint32 _twapInterval,
        uint256 _priceThreshold
    ) public view returns (uint256 price) {
        (uint160 sqrtPrice, uint160 sqrtPriceBefore) = ILiquidBox(box)
            .getSqrtTwapX96(_twapInterval);

        price = FullMath.mulDiv(
            uint256(sqrtPrice).mul(uint256(sqrtPrice)),
            DECIMAL_PREICISION,
            SQRT_PRICE_DENOMINATOR
        );

        uint256 priceBefore = FullMath.mulDiv(
            uint256(sqrtPriceBefore).mul(uint256(sqrtPriceBefore)),
            DECIMAL_PREICISION,
            SQRT_PRICE_DENOMINATOR
        );
        if (
            price.mul(PRICE_PRECISION).div(priceBefore) > _priceThreshold ||
            priceBefore.mul(PRICE_PRECISION).div(price) > _priceThreshold
        ) revert("Price change overflow");
    }

    /// @inheritdoc ILiquidBoxManager
    function getBox(
        address token0,
        address token1,
        uint24 fee
    ) public view override returns (address) {
        return _getBox(token0, token1, fee);
    }

    /// @inheritdoc ILiquidBoxManager
    function getRequiredAmountsForInput(
        address box,
        uint256 deposit0,
        uint256 deposit1
    ) public view override returns (uint256 required0, uint256 required1) {
        int24 _lowerTick = ILiquidBox(box).baseLower();
        int24 _upperTIck = ILiquidBox(box).baseUpper();

        // if box is rebalanced
        if (_lowerTick != 0 && _upperTIck != 0) {
            return
                ILiquidBox(box).getRequiredAmountsForInput(deposit0, deposit1);
        } else {
            return (deposit0, deposit1);
        }
    }

    /// @inheritdoc ILiquidBoxManager
    function balanceOf(
        address box,
        address to
    ) external view override returns (uint256 amount) {
        return IERC20Upgradeable(box).balanceOf(to);
    }

    /// @inheritdoc ILiquidBoxManager
    function getSharesAmount(
        address box,
        address to
    )
        external
        view
        override
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        return
            ILiquidBox(box).getSharesAmount(
                IERC20Upgradeable(box).balanceOf(to)
            );
    }

    /// @inheritdoc ILiquidBoxManager
    function getLimits(
        address box
    ) external view override returns (int24 baseLower, int24 baseUpper) {
        return (ILiquidBox(box).baseLower(), ILiquidBox(box).baseUpper());
    }

    /// @inheritdoc ILiquidBoxManager
    function getTotalAmounts(
        address box
    )
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
        return ILiquidBox(box).getTotalAmounts();
    }

    /// @inheritdoc ILiquidBoxManager
    function getClaimableFees(
        address box,
        address to
    ) external view override returns (uint256 claimable0, uint256 claimable1) {
        return ILiquidBox(box).earnedFees(to);
    }

    /// @inheritdoc ILiquidBoxManager
    function getManagementFees(
        address box
    )
        external
        view
        override
        returns (uint256 claimable0, uint256 claimable1, uint256 emission)
    {
        return ILiquidBox(box).getManagementFees();
    }
}
