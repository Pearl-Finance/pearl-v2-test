// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

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

contract LiquidBoxManager is ILiquidBoxManager, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     *
     *  NON UPGRADEABLE STORAGE
     *
     */

    // uint256 constant MAX_U256 = 2 ** 256 - 1;
    address public factory;
    address public manager;
    address public WETH9;

    /**
     *
     *  EVENTS
     *
     */

    event Deposit(address indexed box, address to, uint256 shares, uint256 amount0, uint256 amount1);
    event Withdraw(address indexed box, address to, uint256 shares, uint256 amount0, uint256 amount1);

    event Rebalance(address indexed box, int24 baseLower, int24 baseUpper, uint256 amount0Min, uint256 amount1Min);

    event ClaimFees(address indexed box, address to, uint256 feesToOwner0, uint256 feesToOwner1);

    event ClaimManagementFee(
        address indexed box, address to, uint256 feesToOwner0, uint256 feesToOwner1, uint256 collectedFeeOnEmission
    );

    event FactoryChanged(address factory);

    event ManagerChanged(address manager);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _intialOwner, address _factory, address _weth9) public initializer {
        require(_intialOwner != address(0) && _factory != address(0), "!zero address");

        __Ownable_init();
        __ReentrancyGuard_init();
        _transferOwnership(_intialOwner);

        factory = _factory;
        manager = _intialOwner;
        WETH9 = _weth9;
    }

    modifier onlyManager() {
        _checkManager();
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

    // =================== Internal  ===================

    function _checkManager() internal view {
        require(msg.sender == manager, "manager");
    }

    /// @notice retreives the box address based on tokens and fee
    function _getBox(address token0, address token1, uint24 fee) internal view returns (address) {
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
        (bool success,) = recipient.call{value: amount}("");
        require(success, "failed inner call");
    }

    // =================== MAIN ===================

    /// @inheritdoc ILiquidBoxManager
    function deposit(address box, uint256 deposit0, uint256 deposit1, uint256 amount0Min, uint256 amount1Min)
        external
        payable
        override
        nonReentrant
        returns (uint256 shares)
    {
        require(deposit0 > 0 || deposit1 > 0, "deposit0 or deposit1");

        // re-calcualte the amounts for a given tick range using the input amounts
        (deposit0, deposit1) = getRequiredAmountsForInput(box, deposit0, deposit1);

        (shares,,) = ILiquidBox(box).deposit(deposit0, deposit1, msg.sender, amount0Min, amount1Min);

        emit Deposit(box, msg.sender, deposit0, deposit1, shares);
    }

    /// @inheritdoc ILiquidBoxManager
    function withdraw(address box, uint256 shares, uint256 amount0Min, uint256 amount1Min)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = ILiquidBox(box).withdraw(shares, msg.sender, amount0Min, amount1Min);
        emit Withdraw(box, msg.sender, shares, amount0, amount1);
    }

    /// @inheritdoc ILiquidBoxManager
    function boxDepositCallback(uint256 amount0Owed, uint256 amount1Owed, address payer) external override {
        (address token0, address token1, uint24 fee) = ILiquidBox(msg.sender).getPoolParams();

        address box = getBox(token0, token1, fee);
        require(box == msg.sender, "!box");

        if (amount0Owed > 0) pay(token0, payer, box, amount0Owed);
        if (amount1Owed > 0) pay(token1, payer, box, amount1Owed);
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
    ) external override nonReentrant {
        require(msg.sender == manager || msg.sender == owner(), "role");
        ILiquidBox(box).rebalance(baseLower, baseUpper, amount0MinBurn, amount1MinBurn, amount0MinMint, amount1MinMint);
        emit Rebalance(box, baseLower, baseUpper, amount0MinMint, amount1MinMint);
    }

    /// @inheritdoc ILiquidBoxManager
    function pullLiquidity(
        address box,
        int24 baseLower,
        int24 baseUpper,
        uint128 shares,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override nonReentrant {
        require(msg.sender == manager || msg.sender == owner(), "role");
        ILiquidBox(box).pullLiquidity(baseLower, baseUpper, shares, amount0Min, amount1Min);
    }

    /// @inheritdoc ILiquidBoxManager
    function claimManagementFees(address box, address to)
        external
        override
        nonReentrant
        onlyOwner
        returns (uint256 collectedfees0, uint256 collectedfees1, uint256 collectedEmission)
    {
        require(box != address(0), "box");
        (collectedfees0, collectedfees1, collectedEmission) = ILiquidBox(box).claimManagementFees(to);
        emit ClaimManagementFee(box, to, collectedfees0, collectedfees1, collectedEmission);
    }

    /// @inheritdoc ILiquidBoxManager
    function claimFees(address box, address to)
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

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(address token, address payer, address recipient, uint256 value) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
            // return the remaining eth amount to the payer
            if (address(this).balance > 0) {
                _sendValue(payable(payer), address(this).balance);
            }
        } else if (payer == address(this)) {
            // pay with tokens already in the contract
            IERC20Upgradeable(token).safeTransfer(recipient, value);
        } else {
            // pull payment
            IERC20Upgradeable(token).safeTransferFrom(payer, recipient, value);
        }
    }

    // =================== VIEW ===================

    /// @inheritdoc ILiquidBoxManager
    function getBox(address token0, address token1, uint24 fee) public view override returns (address) {
        return _getBox(token0, token1, fee);
    }

    /// @inheritdoc ILiquidBoxManager
    function getRequiredAmountsForInput(address box, uint256 deposit0, uint256 deposit1)
        public
        view
        override
        returns (uint256 required0, uint256 required1)
    {
        int24 _lowerTick = ILiquidBox(box).baseLower();
        int24 _upperTIck = ILiquidBox(box).baseUpper();

        // if box is rebalanced
        if (_lowerTick != 0 && _upperTIck != 0) {
            return ILiquidBox(box).getRequiredAmountsForInput(deposit0, deposit1);
        } else {
            return (deposit0, deposit1);
        }
    }

    /// @inheritdoc ILiquidBoxManager
    function balanceOf(address box, address to) external view override returns (uint256 amount) {
        return IERC20Upgradeable(box).balanceOf(to);
    }

    /// @inheritdoc ILiquidBoxManager
    function getSharesAmount(address box, address to)
        external
        view
        override
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        return ILiquidBox(box).getSharesAmount(IERC20Upgradeable(box).balanceOf(to));
    }

    /// @inheritdoc ILiquidBoxManager
    function getLimits(address box) external view override returns (int24 baseLower, int24 baseUpper) {
        return (ILiquidBox(box).baseLower(), ILiquidBox(box).baseUpper());
    }

    /// @inheritdoc ILiquidBoxManager
    function getTotalAmounts(address box)
        external
        view
        override
        returns (uint256 total0, uint256 total1, uint256 pool0, uint256 pool1, uint128 liquidity)
    {
        return ILiquidBox(box).getTotalAmounts();
    }

    /// @inheritdoc ILiquidBoxManager
    function getClaimableFees(address box, address to)
        external
        view
        override
        returns (uint256 claimable0, uint256 claimable1)
    {
        return ILiquidBox(box).earnedFees(to);
    }

    /// @inheritdoc ILiquidBoxManager
    function getManagementFees(address box)
        external
        view
        override
        returns (uint256 claimable0, uint256 claimable1, uint256 emission)
    {
        return ILiquidBox(box).getManagementFees();
    }
}
