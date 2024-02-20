// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/ICrossChainFactory.sol";

abstract contract CrossChainFactoryUpgradeable is ICrossChainFactory, OwnableUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bool public immutable isMainChain;

    // chainId => (srcAddress, destAddress)
    // this function set the trusted path for the cross-chain communication
    mapping(uint16 => mapping(address => address)) public trustedRemoteAddressLookup;

    event SetTrustedRemote(uint16 _remoteChainId, address srcAddress, address destAddress);

    /**
     * @param _mainChainId Chain id of main chain.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(uint256 _mainChainId) {
        isMainChain = _mainChainId == block.chainid;
    }

    function __CrossChainFactory_init() internal onlyInitializing {
        __CrossChainFactory_init_unchained();
        __Ownable_init();
    }

    function __CrossChainFactory_init_unchained() internal onlyInitializing {}

    // this function set the trusted path for the cross-chain communication
    function setTrustedRemoteAddress(uint16 _remoteChainId, address _srcAddress, address _destAddress)
        external
        onlyOwner
    {
        trustedRemoteAddressLookup[_remoteChainId][_srcAddress] = _destAddress;
        emit SetTrustedRemote(_remoteChainId, _srcAddress, _destAddress);
    }

    function getTrustedRemoteAddress(uint16 _chainId, address srcAddress)
        public
        view
        virtual
        override
        returns (address)
    {
        // The factory is instantiated using the create3 factory pattern.
        // All cross-chain contracts created through factory are deterministic and identical.
        // if trustedRemote is set then return trustedRemote else srcAddress
        address trustedRemote = trustedRemoteAddressLookup[_chainId][srcAddress];
        return trustedRemote == address(0) ? srcAddress : trustedRemote;
    }
}
