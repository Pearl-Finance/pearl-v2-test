// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "./IOFTCore.sol";
import "../../../../../../../../../../openzeppelin-08/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface of the OFT standard
 */
interface IOFT is IOFTCore, IERC20 {}
