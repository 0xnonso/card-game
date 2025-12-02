// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TrustedShuffleServiceV0 as TSS} from "../src/TrustedShuffleService.sol";
import {ShuffleProofs} from "./helpers/ShuffleProofs.sol";
import "forge-std/Test.sol";

contract TrustedShuffleServiceTest is Test {
    uint256 constant HANDLES_PER_PROOF = 8;

    TSS internal tss;
    address internal tssAgent = address(0xAA);
    address internal importer = address(0xBEEF);

    function setUp() public {
        tss = new TSS(tssAgent);
        tss.updateImporterApproval(importer, true);
    }

    function testStoreAndUseRealProofs() public {
        bytes[] memory proofs = ShuffleProofs.allProofs();
        uint256 proofsCount = proofs.length;
        uint256 proofSize = proofs[0].length;
        for (uint256 i = 1; i < proofsCount; i++) {
            assertEq(proofs[i].length, proofSize, "proof size mismatch");
        }

        bytes memory blob = new bytes(proofsCount * proofSize);
        for (uint256 i = 0; i < proofsCount; i++) {
            copyBytes(proofs[i], 0, blob, i * proofSize, proofSize);
        }

        vm.prank(tssAgent);
        tss.storeInputProofs(blob, proofsCount, proofSize);

        uint256 proofIdx;
        uint256 handleIdx;
        uint256 totalCalls = (proofsCount * HANDLES_PER_PROOF) / 2;
        for (uint256 callIdx = 0; callIdx < totalCalls; callIdx++) {
            vm.prank(importer);
            bytes memory handlesWithProof = tss.useInputProof();
            (bytes32 h0, bytes32 h1, bytes memory proofData) =
                decodeHandlesWithProof(handlesWithProof, uint16(proofSize));

            bytes memory expectedProof = proofs[proofIdx];
            (bytes32 e0, bytes32 e1) = readHandles(expectedProof, handleIdx);

            assertEq(h0, e0, "handle0 mismatch");
            assertEq(h1, e1, "handle1 mismatch");
            assertEq(proofData, expectedProof, "proof data mismatch");

            handleIdx += 2;
            if (handleIdx == HANDLES_PER_PROOF) {
                handleIdx = 0;
                proofIdx++;
            }
        }

        vm.expectRevert(TSS.InputProofsDepleted.selector);
        vm.prank(importer);
        tss.useInputProof();
    }

    function decodeHandlesWithProof(bytes memory handlesWithProof, uint16 proofSize)
        internal
        pure
        returns (bytes32 handle0, bytes32 handle1, bytes memory proof)
    {
        require(handlesWithProof.length == proofSize + 0x40, "invalid packed proof length");
        assembly {
            handle0 := mload(add(handlesWithProof, 0x20))
            handle1 := mload(add(handlesWithProof, 0x40))
        }
        proof = new bytes(proofSize);
        assembly {
            mcopy(add(proof, 0x20), add(handlesWithProof, 0x60), proofSize)
        }
    }

    function readHandles(bytes memory proof, uint256 handleIndex) internal pure returns (bytes32 h0, bytes32 h1) {
        uint256 offset = 0x20 + 0x02 + (handleIndex * 0x20);
        assembly {
            h0 := mload(add(proof, offset))
            h1 := mload(add(proof, add(offset, 0x20)))
        }
    }

    function copyBytes(bytes memory src, uint256 srcOffset, bytes memory dest, uint256 destOffset, uint256 len)
        internal
        pure
    {
        assembly {
            mcopy(add(add(dest, 0x20), destOffset), add(add(src, 0x20), srcOffset), len)
        }
    }
}
