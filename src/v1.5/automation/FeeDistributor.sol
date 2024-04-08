// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../../interfaces/dex/IPearlV2Factory.sol";
import "../../interfaces/IVoter.sol";
import "../../Epoch.sol";

contract FeeDistributor is OwnableUpgradeable {
    IPearlV2Factory public pairFactory;
    IVoter public voter;
    uint256 public batchSize;
    uint256 public interval;
    uint256 public intervalOffset;

    uint256 private _lastProcessed;
    uint256 private _lastProcessedIndex;
    bool private _isDistributing;

    address[] private _gauges;

    event VoterSet(address voter);
    event IntervalSet(uint256 interval);
    event BatchSizeSet(uint256 batchSize);
    event IntervalOffsetSet(uint256 offset);
    event PairFactorySet(address pairFactory);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _intialOwner, address _pairFactory, address _voter) public initializer {
        __Ownable_init();
        _transferOwnership(_intialOwner);

        require(_pairFactory != address(0) || _voter != address(0), "zero addr");

        pairFactory = IPearlV2Factory(_pairFactory);
        voter = IVoter(_voter);
        batchSize = 20;
        interval = EPOCH_DURATION;
        intervalOffset = 10 minutes;
    }

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        canExec = _isDistributing;
        if (!canExec) {
            uint256 endOfInterval = (block.timestamp / interval) * interval + interval;
            uint256 distributionStartTime = endOfInterval - intervalOffset;
            canExec = block.timestamp > distributionStartTime && _lastProcessed < distributionStartTime;
            if (canExec) {
                canExec = voter.length() > 0;
            }
        }
        if (canExec) {
            execPayload = abi.encodeWithSelector(FeeDistributor.distribute.selector);
        } else {
            execPayload = bytes("Not active");
        }
    }

    function distribute() external {
        if (!_isDistributing) {
            _isDistributing = voter.length() > 0;
        }
        if (_isDistributing) {
            uint256 numGaugePools = voter.length();
            if (numGaugePools > batchSize) {
                numGaugePools = batchSize;
            }
            uint256 from = _lastProcessedIndex;
            uint256 to = MathUpgradeable.min(numGaugePools, from + batchSize);
            voter.distributeFees(from, to);
            bool done = to == numGaugePools;
            _lastProcessedIndex = done ? 0 : to;
            if (done) _isDistributing = false;
            _lastProcessed = block.timestamp;
        }
    }

    function setBatchSize(uint256 _batchSize) external onlyOwner {
        require(_batchSize != 0, "batch size can not be 0");
        batchSize = _batchSize;
        emit BatchSizeSet(_batchSize);
    }

    function setInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 1 hours && _interval <= EPOCH_DURATION, "invalid interval");
        interval = _interval;
        emit IntervalSet(_interval);
    }

    function setIntervalOffset(uint256 _offset) external onlyOwner {
        require(_offset > 0 && _offset < interval, "invalid interval offset");
        intervalOffset = _offset;
        emit IntervalOffsetSet(_offset);
    }

    function setPairFactory(address _pairFactory) external onlyOwner {
        require(_pairFactory != address(0), "zeroAddr");
        pairFactory = IPearlV2Factory(_pairFactory);
        emit PairFactorySet(_pairFactory);
    }

    function setVoter(address _voter) external onlyOwner {
        require(_voter != address(0), "zeroAddr");
        voter = IVoter(_voter);
        emit VoterSet(_voter);
    }
}
