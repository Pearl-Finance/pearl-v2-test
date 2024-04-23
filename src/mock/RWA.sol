// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RWA is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    // uint256 public PRECISION = 100_00;
    // uint256 public FEE = 50;
    // uint256 public totalFees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __ERC20_init("REAL Token", "RWA");
        _transferOwnership(initialOwner);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function testExcluded() public {}
}
