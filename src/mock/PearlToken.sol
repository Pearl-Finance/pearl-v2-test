// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts/token/ERC20/ERC20.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "openzeppelin/contracts/access/Ownable.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract PearlToken is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) Ownable() ERC20Permit(name_) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
