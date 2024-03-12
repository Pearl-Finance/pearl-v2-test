// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "layerzerolabs/lzApp/interfaces/ILayerZeroEndpoint.sol";

/**
 * @title ICrossChainBase
 * @notice Interface for cross-chain base functionality.
 * @dev This interface defines functions for managing trusted remote addresses for cross-chain communication.
 */
interface ICrossChainFactory {
    /**
     * @notice Sets the trusted remote address for a given source address on a remote chain.
     * @param _remoteChainId The ID of the remote chain.
     * @param _srcAddress The source address on the remote chain.
     * @param _destAddress The corresponding destination address on the local chain.
     */
    function setTrustedRemoteAddress(uint16 _remoteChainId, address _srcAddress, address _destAddress) external;

    /**
     * @notice Retrieves the trusted remote address for a given source address on a remote chain.
     * @param chainId The ID of the chain.
     * @param srcAddress The source address on the remote chain.
     * @return The corresponding trusted destination address on the local chain.
     */
    function getTrustedRemoteAddress(uint16 chainId, address srcAddress) external view returns (address);
}
