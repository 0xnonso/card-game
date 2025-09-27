// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./types/PackedInputProof.sol";
import "fhevm/lib/FHE.sol";
import "solady/src/auth/Ownable.sol";

contract TrustedShuffleService is Ownable {
    address public immutable TSS_AGENT;
    address public importer;
    PackedInputProof[] internal inputProofRoots;
    InputProofCursor internal inputProofCursor;

    struct InputProofCursor {
        uint16 remainingHandles;
        uint16 arrayIndex;
        PackedInputProof currentPackedInputProof;
    }

    modifier onlyTssAgent() {
        require(msg.sender == TSS_AGENT, "only tss agent");
        _;
    }

    modifier onlyImporter() {
        require(msg.sender == importer, "only importer");
        _;
    }

    constructor(address tssAgent) {
        TSS_AGENT = tssAgent;
        _initializeOwner(msg.sender);
    }

    event InputProofStored(address ptr, uint16 numProofs, uint16 proofSize);
    event InputProofUsed(uint256 indexed index, uint16 remainingHandles);
    event ImporterChanged(address indexed newImporter);

    function storeInputProofs(bytes calldata packedProofs, uint256 numInputProofs, uint256 proofSize)
        external
        onlyTssAgent
    {
        PackedInputProof memory packedInputProof = PackedInputProofLib.store(packedProofs, numInputProofs, proofSize);
        inputProofRoots.push(packedInputProof);

        emit InputProofStored(packedInputProof.ptr, packedInputProof.numProofs, packedInputProof.proofSize);
    }

    function useInputProof()
        external
        onlyImporter
        returns (externalEuint256 handle1, externalEuint256 handle2, bytes memory proof)
    {
        // how to handle the initial case where there is no currentPackedInputProof?
        InputProofCursor memory cursor = inputProofCursor;
        bool currentPtrIsEmpty = cursor.currentPackedInputProof.ptr == address(0);
        if (cursor.remainingHandles == 0 || currentPtrIsEmpty) {
            cursor.currentPackedInputProof = inputProofRoots[currentPtrIsEmpty ? 0 : cursor.arrayIndex++];
            cursor.remainingHandles = cursor.currentPackedInputProof.numProofs * 4;
        }
        (handle1, handle2, proof) = PackedInputProofLib.get(cursor.currentPackedInputProof, cursor.remainingHandles);
        cursor.remainingHandles--;
        inputProofCursor = cursor;

        emit InputProofUsed(cursor.arrayIndex, cursor.remainingHandles);
    }

    function setProofImporter(address _importer) external onlyOwner {
        importer = _importer;
        emit ImporterChanged(_importer);
    }
}
