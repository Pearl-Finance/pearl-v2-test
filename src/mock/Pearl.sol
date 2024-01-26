// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

contract Pearl is ERC20BurnableUpgradeable {
    address public owner;
    address public minter;
    address public migrator;

    function initialize() public initializer {
        __ERC20_init("Pearl Uno", "PEARL");
        owner = msg.sender;
        minter = msg.sender;
        migrator = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    function reinitialize(address _owner) public reinitializer(11) {
        minter = _owner;
        migrator = _owner;
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function setMigrator(address _migrator) external onlyOwner {
        migrator = _migrator;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function mint(address account, uint256 amount) external returns (bool) {
        require(msg.sender == minter || msg.sender == migrator, "not allowed");
        _mint(account, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        if (spender != migrator) {
            _spendAllowance(from, spender, amount);
        }
        _transfer(from, to, amount);
        return true;
    }
}
