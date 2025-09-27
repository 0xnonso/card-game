// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {externalEuint256} from "fhevm/lib/FHE.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";

struct PackedInputProof {
    uint16 numProofs;
    uint16 proofSize;
    address ptr;
}

using PackedInputProofLib for PackedInputProof global;

library PackedInputProofLib {
    function store(bytes memory data, uint256 numInputProofs, uint256 proofSize)
        internal
        returns (PackedInputProof memory packedInputProof)
    {
        address ptr = SSTORE2.write(data);
        packedInputProof = PackedInputProof({numProofs: uint16(numInputProofs), proofSize: uint16(proofSize), ptr: ptr});
    }

    function get(PackedInputProof memory inputProof, uint256 handleIndex)
        internal
        view
        returns (externalEuint256 handle1, externalEuint256 handle2, bytes memory proof)
    {
        if (handleIndex == 0) {
            revert("handle index out of range");
        }
        // 353 + 65x
        uint256 proofSize = inputProof.proofSize;
        uint256 start = handleIndex * proofSize; //proofIndex * proofSize;
        proof = SSTORE2.read(inputProof.ptr, start, start + proofSize);
        assembly {
            let handle_ptr := mload(add(proof, add(0x22, mul(0x40, handleIndex))))
            handle1 := mload(handle_ptr)
            handle2 := mload(add(handle_ptr, 0x20))
        }
    }
}
