// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ClonesUpgradeable} from "openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {CrossChainFactoryUpgradeable} from "./cross-chain/CrossChainFactoryUpgradeable.sol";

import "./interfaces/box/ILiquidBoxManager.sol";
import "./interfaces/dex/IPearlV2Pool.sol";
import "./interfaces/IGaugeV2.sol";
import "./interfaces/IGaugeV2ALM.sol";
import "./interfaces/IGaugeV2Factory.sol";
import {console2 as console} from "forge-std/Test.sol";

/**
 * @title PearlV2 Gauge Factory for Concentrated Liquidity Pools
 * @author Maverick
 * @notice This factory contract allows the creation of Gauge contracts tailored for PearlV2 Concentrated Liquidity Pools.
 * This factory serves as a deployment hub for customizable gauges, enabling liquidity providers to earn rewards
 * through strategic participation in Concentrated Liquidity Pools.
 */
contract GaugeV2Factory is IGaugeV2Factory, CrossChainFactoryUpgradeable {
    using ClonesUpgradeable for address;

    /**
     *
     *  NON UPGRADEABLE STORAGE
     *
     */

    address public manager;
    address public last_cl_gauge;
    address public last_alm_gauge;
    address public nonfungiblePositionManager;
    address public almManager;

    address public gaugeCLImplementation;
    address public gaugeALMImplementation;

    event setDistributionEvent(address gauge, address newDistribution);
    event setBoxEvent(address gaugeALM, address box);
    event setGaugeALMEvent(address gauge, address gaugeALM);
    event setGaugeCLImplementationEvent(address gaugeCLImplementation);
    event setGaugeALMImplementationEvent(address gaugeALMImplementation);
    event ManagerChanged(address manager);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _mainChainId) CrossChainFactoryUpgradeable(_mainChainId) {
        _disableInitializers();
    }

    function initialize(
        address _intialOwner,
        address _gaugeCLImplementation,
        address _gaugeALMImplementation,
        address _nonFungiblePositionManager,
        address _almManager
    ) public initializer {
        require(
            _gaugeCLImplementation != address(0) && _gaugeALMImplementation != address(0)
                && _nonFungiblePositionManager != address(0) && _almManager != address(0),
            "!zero address"
        );

        __CrossChainFactory_init();
        _transferOwnership(_intialOwner);

        gaugeCLImplementation = _gaugeCLImplementation;
        gaugeALMImplementation = _gaugeALMImplementation;
        nonfungiblePositionManager = _nonFungiblePositionManager;
        almManager = _almManager;
        manager = _intialOwner;
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

    /// @inheritdoc IGaugeV2Factory
    function createGauge(
        uint16 _lzMainChainId,
        uint16 _lzPoolChainId,
        address _factory,
        address _pool,
        address _rewardToken,
        address _distribution,
        address _internalBribe,
        bool _isForPair
    ) external returns (address gauge, address gaugeAlm) {
        bytes32 salt = keccak256(abi.encodePacked(_lzPoolChainId, _pool, "CL"));
        gauge = gaugeCLImplementation.cloneDeterministic(salt);

        IGaugeV2(gauge).initialize(
            isMainChain,
            _lzMainChainId,
            _lzPoolChainId,
            _factory,
            _pool,
            nonfungiblePositionManager,
            _rewardToken,
            _distribution,
            _internalBribe,
            _isForPair
        );

        // only allowed on pool chain
        if ((isMainChain && _lzMainChainId == _lzPoolChainId) || (!isMainChain && _lzMainChainId != _lzPoolChainId)) {
            //create gauge for ALM LP tokens
            gaugeAlm = _createGaugeALM(_lzPoolChainId, _pool, _rewardToken, gauge);
            //set alm gauge in master gauge
            IGaugeV2(gauge).setALMGauge(gaugeAlm);
        }

        last_cl_gauge = gauge;
    }

    /// @notice Create gaue for alm LP tokens
    /// @dev gaugeALM must be deployed along with the master gauge.
    function _createGaugeALM(uint16 _lzPoolChainId, address _pool, address _rewardToken, address _gaugeCL)
        internal
        returns (address gauge)
    {
        IPearlV2Pool iPool = IPearlV2Pool(_pool);
        address _almManager = almManager;
        address _almBox = ILiquidBoxManager(_almManager).getBox(iPool.token0(), iPool.token1(), iPool.fee());

        bytes32 salt = keccak256(abi.encodePacked(_lzPoolChainId, _pool, "ALM"));
        gauge = gaugeALMImplementation.cloneDeterministic(salt);
        IGaugeV2ALM(gauge).initialize(_lzPoolChainId, _rewardToken, _almBox, _gaugeCL, _almManager);
        last_alm_gauge = gauge;
    }

    /**
     * @notice Sets a new reward distribution address for a specified gauge.
     * @dev This function can only be called by the owner of the contract.
     * @param _gauge The address of the gauge for which the distribution contract is being updated.
     * @param _newDistribution The address of the new distribution contract.
     */
    function setDistribution(address _gauge, address _newDistribution) external onlyOwner {
        IGaugeV2(_gauge).setDistribution(_newDistribution);
        emit setDistributionEvent(_gauge, _newDistribution);
    }

    /// @dev Sets the manager of the factory.
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerChanged(_manager);
    }

    /**
     * @notice Sets a new gauge ALM address for a specified main gauge.
     * @dev This function can only be called by the owner of the contract.
     * @param _gauge The address of the gauge for which the distribution contract is being updated.
     * @param _gaugeALM The address of the new alm gauge contract.
     */
    function setGaugeALM(address _gauge, address _gaugeALM) external onlyAllowed {
        IGaugeV2(_gauge).setALMGauge(_gaugeALM);
        emit setGaugeALMEvent(_gauge, _gaugeALM);
    }

    /**
     * @notice Sets a new alm box for a specified gauge ALM address.
     * @dev This function can only be called by the owner of the contract.
     * @param _gaugeALM The address of the new alm gauge contract.
     * @param _box The address of the alm box
     */
    function setBox(address _gaugeALM, address _box) external onlyAllowed {
        IGaugeV2ALM(_gaugeALM).setBox(_box);
        emit setBoxEvent(_gaugeALM, _box);
    }

    /**
     * @notice Sets a new gauge CL implementation address
     * @dev This function can only be called by the owner of the contract.
     * @param _gaugeCLImplementation The address of the new gauge implementation.
     */
    function setGaugeCLImplementation(address _gaugeCLImplementation) external onlyOwner {
        require(_gaugeCLImplementation != address(0), "!zero address");
        gaugeCLImplementation = _gaugeCLImplementation;
        emit setGaugeCLImplementationEvent(_gaugeCLImplementation);
    }

    /**
     * @notice Sets a new gauge ALM implementation address
     * @dev This function can only be called by the owner of the contract.
     * @param _gaugeALMImplementation The address of the new gauge implementation.
     */
    function setGaugeALMIMplementation(address _gaugeALMImplementation) external onlyOwner {
        require(_gaugeALMImplementation != address(0), "!zero address");
        gaugeALMImplementation = _gaugeALMImplementation;
        emit setGaugeALMImplementationEvent(_gaugeALMImplementation);
    }
}
