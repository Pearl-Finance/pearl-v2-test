// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Box is Initializable, OwnableUpgradeable {
    uint256 public value;

    function initialize(uint256 _value, address _owner) public initializer {
        __Ownable_init();
        transferOwnership(_owner);
        value = _value;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Emitted when the stored value changes
    event ValueChanged(uint256 newValue);

    // Stores a new value in the contract
    function store(uint256 newValue) public onlyOwner {
        value = newValue;
        emit ValueChanged(newValue);
    }

    // Reads the last stored value
    function retrieve() public view returns (uint256) {
        return value;
    }

    function testExcluded() public {}
}
