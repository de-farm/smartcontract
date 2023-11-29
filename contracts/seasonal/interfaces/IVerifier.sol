// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IVerifier {
    function getDivestDigest(
        address _farm,
        address _asset,
        bytes memory _info
    ) external view returns (bytes32);

    function recoverSigner(bytes memory signature, bytes32 digest) external pure returns(address);
}
