// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {einput} from "fhevm/lib/FHE.sol";
// import {SSTORE2} from "solady/src/utils/SSTORE2.sol";

// type ShuffledCardDeckKey is bytes22;

// type ShuffledCardDeckKeyIndex is uint16;
// // arrayIndex| ptrIndex

// // uint8| uint8 | uint160
// // used input proofs|total input proofs| num of kms signers| address

// using ShuffledCardDeckKeyLib for ShuffledCardDeckKey global;
// using ShuffledCardDeckKeyLib for ShuffledCardDeckKeyIndex global;

// library ShuffledCardDeckKeyLib {
//     function getPtr(ShuffledCardDeckKey key) internal pure returns (address ptr) {
//         assembly {
//             ptr := and(key, 0xffffffffffffffff)
//         }
//     }

//     function getNumKmsSigners(ShuffledCardDeckKey key)
//         internal
//         pure
//         returns (uint256 numKmsSigners)
//     {
//         assembly {
//             numKmsSigners := and(shr(160, key), 0xff)
//         }
//     }

//     function getNumInputProofs(ShuffledCardDeckKey key)
//         internal
//         pure
//         returns (uint256 numInputProofs)
//     {
//         assembly {
//             numInputProofs := and(shr(168, key), 0xff)
//         }
//     }

//     function getUsedNumInputProof(ShuffledCardDeckKeyIndex index) internal pure returns (uint256) {
//         return uint256(ShuffledCardDeckKeyIndex.unwrap(index) & 0xff);
//     }

//     function getCurrentIndex(ShuffledCardDeckKeyIndex index) internal pure returns (uint256) {
//         return uint256(ShuffledCardDeckKeyIndex.unwrap(index) >> 8);
//     }

//     function useKey(ShuffledCardDeckKey key, ShuffledCardDeckKeyIndex index)
//         internal
//         pure
//         returns (ShuffledCardDeckKeyIndex newIndex)
//     {
//         uint256 numInputProofs = key.getNumInputProofs();
//         if (index.getUsedNumInputProof() > key.getNumInputProofs()) {
//             newIndex = ShuffledCardDeckKeyIndex.wrap(ShuffledCardDeckKeyIndex.unwrap(index) + 1);
//         } else {
//             newIndex = ShuffledCardDeckKeyIndex.wrap(
//                 (ShuffledCardDeckKeyIndex.unwrap(index) & 0xff00) + 256
//             );
//         }
//     }

//     function storeInputHandleWithProof(
//         bytes memory data,
//         uint256 numInputProofs,
//         uint256 numKmsSigners
//     ) internal returns (ShuffledCardDeckKey key) {
//         address ptr = SSTORE2.write(data);
//         assembly {
//             key := or(ptr, or(shl(208, numInputProofs), shl(160, numKmsSigners)))
//         }
//     }

//     function getInputHandleWithProof(ShuffledCardDeckKey key, ShuffledCardDeckKeyIndex index)
//         internal
//         view
//         returns (einput handle1, einput handle2, bytes memory inputProof)
//     {
//         // 353 + 65x
//         uint256 numKmsSigners = key.getNumKmsSigners();
//         uint256 proofIndex = index.getUsedNumInputProof();
//         uint256 proofSize = 0x161 + 0x41 * numKmsSigners;
//         uint256 start = proofIndex * proofSize;
//         bytes memory rawData = SSTORE2.read(key.getPtr(), start, start + proofSize);
//         assembly {
//             let handle_ptr := mload(add(rawData, add(0x22, mul(0x40, proofIndex))))
//             handle1 := mload(handle_ptr)
//             handle2 := mload(add(handle_ptr, 0x20))
//         }
//         inputProof = bytes.concat(abi.encodePacked(uint8(8), uint8(numKmsSigners)), rawData);
//     }
// }
