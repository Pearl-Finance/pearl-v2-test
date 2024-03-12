// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IV2SwapRouter.sol";
import "../ISwapRouter.sol";

/// @title Router token swapping functionality
interface ISwapRouter02 is IV2SwapRouter, ISwapRouter {}
