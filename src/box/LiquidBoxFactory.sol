// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "../interfaces/dex/IPearlV2Factory.sol";
import "../interfaces/box/ILiquidBoxFactory.sol";
import "../interfaces/box/ILiquidBox.sol";

/**
 * @title Active Liquidity Management Factory for PearlV2 Concentrated Liquidity Pools
 * @author Maverick
 * @notice This factory contract allows the creation of Active Liquidity Management Contracts
 * for PearlV2 Concentrated Liquidity Pools, providing flexible strategies for liquidity provision.
 * Users can deploy new management contracts to actively manage liquidity across different pools.
 * This factory contract serves as a deployment hub for customized liquidity management strategies.
 * The created contracts employ tactics such as Narrow Range or Wide Range strategies for liquidity concentration.
 * For detailed function descriptions and deployed contract usage, refer to protocol documentaion.
 */

contract LiquidBoxFactory is ILiquidBoxFactory, OwnableUpgradeable {
    using ClonesUpgradeable for address;

    /**
     *
     *  NON UPGRADEABLE STORAGE
     *
     */

    address public manager;
    address public override boxManager;
    address public boxImplementation;
    address[] public boxes;

    IPearlV2Factory public pearlV2Factory;

    mapping(address => mapping(address => mapping(uint24 => address))) public getBox; // toke0, token1, fee -> box address

    /**
     *
     *  EVENTS
     *
     */

    event BoxCreated(address token0, address token1, uint24 fee, address box, uint256);

    event ManagerChanged(address manager);
    event BoxManagerChanged(address boxManager);
    event SetBoxImplementation(address boxImplementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _intialOwner, address _pearlV2Factory, address _boxImplementation) public initializer {
        require(
            _intialOwner != address(0) && _pearlV2Factory != address(0) && _boxImplementation != address(0),
            "!zero address"
        );

        __Ownable_init();
        _transferOwnership(_intialOwner);

        manager = _intialOwner;
        boxImplementation = _boxImplementation;
        pearlV2Factory = IPearlV2Factory(_pearlV2Factory);
    }

    /**
     * @dev Throws if called by any account other than the manager.
     */
    modifier onlyAllowed() {
        _checkRole();
        _;
    }

    /**
     * @dev Throws if the sender is not the manager.
     */
    function _checkRole() internal view virtual {
        require(owner() == _msgSender() || manager == _msgSender(), "caller doesn't have permission");
    }

    function createLiquidBox(address tokenA, address tokenB, uint24 fee, string memory name, string memory symbol)
        external
        onlyAllowed
        returns (address box)
    {
        require(tokenA != tokenB, "token");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "zero address");

        address pool = pearlV2Factory.getPool(token0, token1, fee);
        require(pool != address(0), "pool");
        require(getBox[token0][token1][fee] == address(0), "box exists");

        int24 tickSpacing = pearlV2Factory.feeAmountTickSpacing(fee);

        bytes32 salt = keccak256(abi.encodePacked(token0, token1, fee, tickSpacing));
        box = boxImplementation.cloneDeterministic(salt);
        ILiquidBox(box).initialize(
            pool,
            address(this), // owner
            address(this),
            name,
            symbol
        );

        getBox[token0][token1][fee] = box;
        getBox[token1][token0][fee] = box;
        boxes.push(box);
        emit BoxCreated(token0, token1, fee, box, boxes.length);
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerChanged(_manager);
    }

    function setBoxManager(address _boxManager) external onlyOwner {
        boxManager = _boxManager;
        emit BoxManagerChanged(_boxManager);
    }

    function setBoxImplementation(address _boxImplementation) external onlyOwner {
        boxImplementation = _boxImplementation;
        emit SetBoxImplementation(_boxImplementation);
    }

    /// @notice set owner of the contract
    function setOwner(address box, address _owner) external onlyOwner {
        ILiquidBox(box).setOwner(_owner);
    }

    /// @notice set management fee
    function setFee(address box, uint24 newFee) external onlyOwner {
        ILiquidBox(box).setFee(newFee);
    }

    function setMaxTotalSupply(address box, uint256 _maxTotalSupply) external onlyAllowed {
        ILiquidBox(box).setMaxTotalSupply(_maxTotalSupply);
    }

    /// @notice Toggle Direct Deposit
    function toggleDirectDeposit(address box) external onlyAllowed {
        ILiquidBox(box).toggleDirectDeposit();
    }

    /// @notice set manager of the contract
    function setGauge(address box, address gauge) external onlyAllowed {
        ILiquidBox(box).setGauge(gauge);
    }
}
