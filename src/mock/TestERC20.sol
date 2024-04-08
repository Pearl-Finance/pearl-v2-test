// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Test ERC20", "TEST") {}

    function mint(address addr, uint256 amt) external {
        _mint(addr, amt);
    }
}
