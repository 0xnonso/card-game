// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TrustedShuffleServiceV0 as TSS} from "../src/TrustedShuffleService.sol";
import {WhotCardStandardLibx8} from "../src/libraries/WhotCardDeck.sol";
import {DummyShuffledProofs} from "./helpers/DummyShuffledProofs.sol";

import "forge-std/Test.sol";
import "solady/src/utils/LibBytes.sol";

contract TrustedShuffleServiceTest is Test {
    uint256 constant HANDLES_PER_PROOF = 8;

    TSS internal tss;
    address internal tssAgent = address(0xAA);
    address internal importer = address(0xBEEF);

    function setUp() public {
        tss = new TSS(tssAgent, WhotCardStandardLibx8.getDefaultDeck());
        tss.updateImporterApproval(importer, true);
    }

    function testStoreAndInputProofs() public {
        bytes memory proofs;
        for (uint256 i = 0; i < DummyShuffledProofs.allProofs().length; i++) {
            proofs = bytes.concat(proofs, DummyShuffledProofs.allProofs()[i]);
        }
        vm.prank(tssAgent);
        tss.storeInputProofs(
            proofs,
            keccak256(abi.encode(WhotCardStandardLibx8.getDefaultDeck())),
            DummyShuffledProofs.allProofs().length,
            DummyShuffledProofs.allProofs()[0].length,
            true
        );
        for (uint256 i = 0; i < DummyShuffledProofs.allProofs().length; i++) {
            for (uint256 j = 0; j < HANDLES_PER_PROOF / 2; j++) {
                vm.prank(importer);
                bytes memory handlesWithProof = tss.useInputProof();
                bytes memory proof = LibBytes.slice(handlesWithProof, 64);
                bytes memory expectedProof = DummyShuffledProofs.allProofs()[i];
                assertEq(proof, expectedProof);
                uint256 expectedHandleOffset = (j * 64) + 2;
                assertEq(
                    LibBytes.slice(handlesWithProof, 0, 64),
                    LibBytes.slice(expectedProof, expectedHandleOffset, expectedHandleOffset + 64)
                );
            }
        }
    }
}
