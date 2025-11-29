// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";

contract TrustedShuffleServiceV0 is Ownable {
    uint256 constant HANDLES_PER_PROOF = 8;

    address immutable TSS_AGENT;

    /// @dev computed from keccak256(bytes("TrustedShuffleService.v0.Identifier"))
    bytes32 constant INPUT_PROOF_ID_HASH = 0x33d498b8afe92ab958356853549971d23806d0c1a084c55e48fecb624b5ef06d;

    struct ProofCursor {
        uint16 totalNumPtrs;
        uint16 usedHandles;
        uint16 ptrIndex;
    }

    struct PointerMeta {
        uint32 totalHandles;
        uint16 proofSize;
    }

    ProofCursor internal proofCursor;
    mapping(uint256 ptrIndex => PointerMeta) internal pointerMeta;
    mapping(address importer => bool) internal approvedImporters;

    error OnlyTssAgent();
    error OnlyApprovedImporter();
    error InputProofsDepleted();
    error InvalidInputProofBlob();
    error InvalidProofPayload();

    event ImporterApprovalUpdated(address indexed importer, bool approved);
    event InputProofStored(address indexed ptr, uint256 proofsStored, uint256 proofSize);
    event InputProofUsed(address indexed ptr, uint256 proofIndex);

    constructor(address tssAgent) {
        TSS_AGENT = tssAgent;
        _initializeOwner(msg.sender);
    }

    modifier onlyTssAgent() {
        if (msg.sender != TSS_AGENT) revert OnlyTssAgent();
        _;
    }

    modifier onlyImporter() {
        if (!approvedImporters[msg.sender]) revert OnlyApprovedImporter();
        _;
    }

    function storeInputProofs(bytes calldata proofs, uint256 numProofs, uint256 proofSize) external onlyTssAgent {
        if (proofs.length == 0 || (proofs.length != (numProofs * proofSize))) {
            revert InvalidProofPayload();
        }
        ProofCursor storage cursor = proofCursor;
        uint256 ptrIndex = cursor.totalNumPtrs;
        address ptr = SSTORE2.writeDeterministic(proofs, deriveSalt(ptrIndex));
        pointerMeta[ptrIndex] =
            PointerMeta({totalHandles: uint32(HANDLES_PER_PROOF * numProofs), proofSize: uint16(proofSize)});
        cursor.totalNumPtrs++;

        emit InputProofStored(ptr, numProofs, proofSize);
    }

    function useInputProof() external onlyImporter returns (bytes memory handlesWithProof) {
        ProofCursor memory cursor = proofCursor;
        PointerMeta memory ptrMeta = pointerMeta[cursor.ptrIndex];
        if (ptrMeta.totalHandles == cursor.usedHandles) {
            cursor.ptrIndex++;
            cursor.usedHandles = 0;
        }
        if (cursor.ptrIndex >= cursor.totalNumPtrs) {
            revert InputProofsDepleted();
        }
        address ptr = SSTORE2.predictDeterministicAddress(deriveSalt(cursor.ptrIndex), address(this));
        uint256 proofIndex = cursor.usedHandles / HANDLES_PER_PROOF;
        uint16 proofSize = ptrMeta.proofSize;
        uint256 start = proofIndex * proofSize;
        // input proof layout:
        // - len(list_handles)    = (1 byte)
        // - numSignersKMS        = (1 byte)
        // - list_handles         = (NUM_HANDLES * 32 bytes)
        // - signatures           = (numSignersKMS * 65 bytes)  // ECDSA signatures over handles + extraData
        // - extraData            = (variable)
        //   Total = 2 + NUM_HANDLES * 32 + (65 * numSignersKMS) + extraData.length
        bytes memory proof = SSTORE2.read(ptr, start, start + proofSize);

        if (proof.length != proofSize) revert InvalidInputProofBlob();

        handlesWithProof = new bytes(proofSize + 0x40);
        uint256 handleIndex = cursor.usedHandles % HANDLES_PER_PROOF;
        uint256 handleOffset = 0x02 + (handleIndex * 0x20);
        assembly {
            let dest := add(handlesWithProof, 0x20)
            let dataPtr := add(proof, 0x20)
            let handlePos := add(dataPtr, handleOffset)
            mcopy(dest, handlePos, 0x40)
            mcopy(add(dest, 0x40), dataPtr, proofSize)
        }
        cursor.usedHandles += 2;
        proofCursor = cursor;

        emit InputProofUsed(ptr, proofIndex);
    }

    function deriveSalt(uint256 index) internal view returns (bytes32 salt) {
        assembly {
            let fmp := mload(0x40)
            mstore(0x00, INPUT_PROOF_ID_HASH)
            mstore(0x20, address())
            mstore(0x40, index)
            salt := keccak256(0x00, 0x60)
            mstore(0x40, fmp)
        }
    }

    function updateImporterApproval(address _importer, bool approved) external onlyOwner {
        approvedImporters[_importer] = approved;
        emit ImporterApprovalUpdated(_importer, approved);
    }

    function isApprovedImporter(address _importer) external view returns (bool) {
        return approvedImporters[_importer];
    }
}
