// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

import "./interfaces/box/ILiquidBoxManager.sol";
import "./interfaces/dex/IPearlV2Pool.sol";
import "./interfaces/IGaugeV2.sol";
import "./interfaces/IGaugeV2ALM.sol";
import "./interfaces/IGaugeV2Factory.sol";

/**
 * @title PearlV2 Gauge Factory for Concentrated Liquidity Pools
 * @author Maverick
 * @notice This factory contract allows the creation of Gauge contracts tailored for PearlV2 Concentrated Liquidity Pools.
 * This factory serves as a deployment hub for customizable gauges, enabling liquidity providers to earn rewards
 * through strategic participation in Concentrated Liquidity Pools.
 */
contract GaugeV2Factory is IGaugeV2Factory, OwnableUpgradeable {
    using ClonesUpgradeable for address;

    /************************************************
     *  NON UPGRADEABLE STORAGE
     ***********************************************/

    address public last_cl_gauge;
    address public last_alm_gauge;
    address public nonfungiblePositionManager;
    address public almManager;

    address public gaugeCLImplementation;
    address public gaugeALMImplementation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _gaugeCLImplementation,
        address _gaugeALMImplementation,
        address _nonfungiblePositionManager,
        address _almManager
    ) public initializer {
        __Ownable_init();
        gaugeCLImplementation = _gaugeCLImplementation;
        gaugeALMImplementation = _gaugeALMImplementation;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        almManager = _almManager;
    }

    /// @inheritdoc IGaugeV2Factory
    function createGauge(
        address _factory,
        address _pool,
        address _rewardToken,
        address _distribution,
        address _internalBribe,
        bool _isForPair
    ) external returns (address gauge, address gaugeAlm) {
        gauge = gaugeCLImplementation.clone();
        IGaugeV2(gauge).initialize(
            _factory,
            _pool,
            nonfungiblePositionManager,
            _rewardToken,
            _distribution,
            _internalBribe,
            _isForPair
        );

        //create gauge for ALM LP tokens
        gaugeAlm = _createGaugeALM(_pool, _rewardToken, gauge);
        //set alm gauge in master gauge
        IGaugeV2(gauge).setALMGauge(gaugeAlm);

        last_cl_gauge = gauge;
    }

    /// @notice Create gaue for alm LP tokens
    /// @dev gaugeALM must be deployed along with the master gauge.
    function _createGaugeALM(
        address _pool,
        address _rewardToken,
        address _gaugeCL
    ) internal returns (address gauge) {
        IPearlV2Pool iPool = IPearlV2Pool(_pool);
        address _almManager = almManager;
        address _almBox = ILiquidBoxManager(_almManager).getBox(
            iPool.token0(),
            iPool.token1(),
            iPool.fee()
        );

        gauge = gaugeALMImplementation.clone();
        IGaugeV2ALM(gauge).initialize(
            _rewardToken,
            _almBox,
            _gaugeCL,
            _almManager
        );
        last_alm_gauge = gauge;
    }

    /**
     * @notice Sets a new reward distribution address for a specified gauge.
     * @dev This function can only be called by the owner of the contract.
     * @param _gauge The address of the gauge for which the distribution contract is being updated.
     * @param _newDistribution The address of the new distribution contract.
     */
    function setDistribution(
        address _gauge,
        address _newDistribution
    ) external onlyOwner {
        IGaugeV2(_gauge).setDistribution(_newDistribution);
    }

    /**
     * @notice Sets a new gauge ALM address for a specified main gauge.
     * @dev This function can only be called by the owner of the contract.
     * @param _gauge The address of the gauge for which the distribution contract is being updated.
     * @param _gaugeALM The address of the new alm gauge contract.
     */
    function setGaugeALM(address _gauge, address _gaugeALM) external onlyOwner {
        IGaugeV2(_gauge).setALMGauge(_gaugeALM);
    }

    /**
     * @notice Sets a new alm box for a specified gauge ALM address.
     * @dev This function can only be called by the owner of the contract.
     * @param _gaugeALM The address of the new alm gauge contract.
     * @param _box The address of the alm box
     */
    function setBox(address _gaugeALM, address _box) external onlyOwner {
        IGaugeV2ALM(_gaugeALM).setBox(_box);
    }
}
