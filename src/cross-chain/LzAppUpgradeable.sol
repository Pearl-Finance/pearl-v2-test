// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {OwnableUpgradeable} from "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "layerzerolabs/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "layerzerolabs/lzApp/interfaces/ILayerZeroReceiver.sol";

abstract contract LzAppUpgradeable is OwnableUpgradeable, ILayerZeroReceiver {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILayerZeroEndpoint public immutable lzEndpoint;

    // bytes = abi.encodePacked(remoteAddress, localAddress)
    // this function set the trusted path for the cross-chain communication
    mapping(uint16 => bytes) public trustedRemoteLookup;

    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);

    /**
     * @param _endpoint Address of the LayerZero endpoint contract.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address _endpoint) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
    }

    function __LzApp_init() internal onlyInitializing {
        __LzApp_init_unchained();
        __Ownable_init();
    }

    function __LzApp_init_unchained() internal onlyInitializing {}

    // _path = abi.encodePacked(remoteAddress, localAddress)
    // this function set the trusted path for the cross-chain communication
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external onlyOwner {
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemote(_remoteChainId, _path);
    }

    /**
     * @dev Internal function to send a LayerZero message to a destination chain.
     * It performs a series of validations before sending the message.
     *
     * Requirements:
     * - Destination chain must be a trusted remote.
     * - Payload size must be within the configured limit.
     *
     * @param dstChainId The ID of the destination chain.
     * @param payload The actual data payload to be sent.
     * @param refundAddress The address to which any refunds should be sent.
     * @param zroPaymentAddress The address for the ZRO token payment.
     * @param adapterParams Additional parameters required for the adapter.
     * @param nativeFee The native fee to be sent along with the message.
     */
    function _lzSend(
        uint16 dstChainId,
        bytes memory payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams,
        uint256 nativeFee
    ) internal virtual {
        bytes memory trustedRemote = getTrustedRemote(dstChainId);
        require(trustedRemote.length != 0, "LzApp: destination chain is not a trusted source");
        _checkPayloadSize(dstChainId, payload.length);
        lzEndpoint.send{value: nativeFee}(
            dstChainId, trustedRemote, payload, refundAddress, zroPaymentAddress, adapterParams
        );
    }

    /**
     * @dev Handles incoming LayerZero messages from a source chain.
     * This function must be called by the LayerZero endpoint and validates the source of the message.
     *
     * Requirements:
     * - Caller must be the LayerZero endpoint.
     * - Source address must be a trusted remote address.
     *
     * @param srcChainId The ID of the source chain from which the message is sent.
     * @param srcAddress The address on the source chain that is sending the message.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data payload of the message.
     */
    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        virtual
        override
    {
        // lzReceive must be called by the endpoint for security
        require(_msgSender() == address(lzEndpoint), "LzApp: invalid endpoint caller");

        bytes memory trustedRemote = trustedRemoteLookup[srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from
        // untrusted remote.
        require(
            srcAddress.length == trustedRemote.length && trustedRemote.length != 0
                && keccak256(srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );

        _blockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function _checkPayloadSize(uint16, uint256) internal view virtual {
        return;
    }

    /**
     * @dev Internal function that handles incoming LayerZero messages in a blocking manner.
     * This is an abstract function and should be implemented by derived contracts.
     *
     * @param srcChainId The ID of the source chain from which the message is sent.
     * @param srcAddress The address on the source chain that is sending the message.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data payload of the message.
     */
    function _blockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual;

    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool) {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }

    function getTrustedRemote(uint16 _chainId) public view returns (bytes memory trustedRemote) {
        trustedRemote = trustedRemoteLookup[_chainId];
    }

    // generic config for LayerZero user Application
    function setConfig(uint16 _version, uint16 _chainId, uint256 _configType, bytes calldata _config)
        external
        onlyOwner
    {
        lzEndpoint.setConfig(_version, _chainId, _configType, _config);
    }
}
