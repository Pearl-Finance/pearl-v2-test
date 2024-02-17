// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/ICrossChainFactory.sol";

interface IBribeFactory is ICrossChainFactory {
  /**
   * @notice Struct for converting tokens.
   * @param target Target address for conversion.
   * @param selector Function selector for the conversion.
   */
  struct ConvertData {
    address target;
    bytes4 selector;
  }

  function createInternalBribe(address[] memory) external returns (address);

  function createExternalBribe(address[] memory) external returns (address);

  function createBribe(
    uint16 _lzMainChainId,
    uint16 _lzPoolChainId,
    address _pool,
    address _owner,
    address _token0,
    address _token1,
    string memory _type
  ) external returns (address);

  /**
   * @notice Retrieves the address of the keeper.
   * @return Address of the keeper contract.
   */
  function keeper() external view returns (address);

  /**
   * @notice Retrieves the address of the USTB (US T-BILL).
   * @return Address of the USTB contract.
   */
  function ustb() external view returns (address);

  /**
   * @notice Retrieves the main chain ID.
   * @return Main chain ID.
   */
  function mainChainId() external view returns (uint16);

  /**
   * @notice Retrieves the conversion data for a target address.
   * @param target Target address for conversion.
   * @return ConvertData struct containing the target and function selector.
   */
  function convertData(
    address target
  ) external view returns (ConvertData memory);
}
