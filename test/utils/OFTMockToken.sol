// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BytesLib} from "layerzerolabs/libraries/BytesLib.sol";
import {OFTMock} from "layerzerolabs/token/oft/v1/mocks/OFTMock.sol";

contract OFTMockToken is OFTMock {
    using BytesLib for bytes;

    constructor(address _lzEndpoint) OFTMock(_lzEndpoint) {}

    function _sendAck(uint16 _srcChainId, bytes memory srcAddressBytes, uint64, bytes memory _payload)
        internal
        override
    {
        (, bytes memory toAddressBytes, uint256 amount) = abi.decode(_payload, (uint16, bytes, uint256));

        address src = srcAddressBytes.toAddress(0);
        address to = toAddressBytes.toAddress(0);

        // send the acknowledgement to the receiver for the amount credited from the source chain
        bool success;
        bytes4 sig = bytes4(keccak256("notifyCredit(uint16,address,address,address,uint256)"));
        bytes memory data = abi.encodeWithSelector(sig, _srcChainId, to, src, address(this), amount);
        assembly {
            success :=
                call(
                    gas(), // gas remaining
                    to, // destination address
                    0, // no ether
                    add(data, 32), // input buffer (starts after the first 32 bytes in the `data` array)
                    mload(data), // input length (loaded from the first 32 bytes in the `data` array)
                    0, // output buffer
                    0 // output length
                )
        }

        amount = _creditTo(_srcChainId, to, amount);
        emit ReceiveFromChain(_srcChainId, to, amount);
    }

    function testExcluded() public {}
}
