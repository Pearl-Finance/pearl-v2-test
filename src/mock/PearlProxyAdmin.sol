// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract PearlProxyAdmin is ProxyAdmin {
    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }
}
