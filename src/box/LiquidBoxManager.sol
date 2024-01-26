// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/box/ILiquidBox.sol";
import "../interfaces/box/ILiquidBoxFactory.sol";
import "../interfaces/box/ILiquidBoxManager.sol";

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

    /************************************************
     *  NON UPGRADEABLE STORAGE
     ***********************************************/

    uint256 constant MAX_U256 = 2 ** 256 - 1;
    address public factory;
    address public manager;

    /************************************************
     *  EVENTS
     ***********************************************/

    /// events

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

    event ClaimFee(
        address indexed box,
        address to,
        uint256 feesToOwner0,
        uint256 feesToOwner1
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _factory) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        factory = _factory;
        manager = msg.sender;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "manager");
        _;
    }

    /// @inheritdoc ILiquidBoxManager
    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    /// @notice set manager to manage deposited funds
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    // =================== Internal  ===================

    /// @notice retreives the box address based on tokens and fee
    function _getBox(
        address token0,
        address token1,
        uint24 fee
    ) internal view returns (address) {
        return ILiquidBoxFactory(factory).getBox(token0, token1, fee);
    }

    // =================== MAIN ===================

    /// @inheritdoc ILiquidBoxManager
    function deposit(
        address box,
        uint256 deposit0,
        uint256 deposit1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override nonReentrant returns (uint256 shares) {
        if (deposit0 > 0) {
            ILiquidBox(box).token0().safeTransferFrom(
                msg.sender,
                address(this),
                deposit0
            );
            ILiquidBox(box).token0().safeApprove(box, deposit0);
        }

        if (deposit1 > 0) {
            ILiquidBox(box).token1().safeTransferFrom(
                msg.sender,
                address(this),
                deposit1
            );
            ILiquidBox(box).token1().safeApprove(box, deposit1);
        }

        (shares, , ) = ILiquidBox(box).deposit(
            deposit0,
            deposit1,
            msg.sender,
            amount0Min,
            amount1Min
        );

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
            amount0Min,
            amount1Min
        );
        emit Withdraw(box, msg.sender, shares, amount0, amount1);
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
    ) external override nonReentrant {
        require(msg.sender == manager || msg.sender == owner(), "role");
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
        address box,
        address to
    )
        external
        override
        nonReentrant
        onlyOwner
        returns (uint256 collectedfees0, uint256 collectedfees1)
    {
        require(box != address(0), "box");
        (collectedfees0, collectedfees1) = ILiquidBox(box).claimManagementFees(
            to
        );
        emit ClaimFee(box, to, collectedfees0, collectedfees1);
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
        emit ClaimFee(box, to, collectedfees0, collectedfees1);
    }

    // =================== VIEW ===================

    /// @inheritdoc ILiquidBoxManager
    function getBox(
        address token0,
        address token1,
        uint24 fee
    ) external view override returns (address) {
        return _getBox(token0, token1, fee);
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
}
