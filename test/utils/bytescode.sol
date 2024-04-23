// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

library BytesCode {
    function deployCode(bytes memory bytecode) internal returns (address payable addr) {
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))

            if iszero(extcodesize(addr)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function getContractCreationCode(address logic) internal pure returns (bytes memory) {
        bytes10 creation = 0x3d602d80600a3d3981f3;
        bytes10 prefix = 0x363d3d373d3d3d363d73;
        bytes20 targetBytes = bytes20(logic);
        bytes15 suffix = 0x5af43d82803e903d91602b57fd5bf3;
        return abi.encodePacked(creation, prefix, targetBytes, suffix);
    }

    function testExcluded() public {}
}
