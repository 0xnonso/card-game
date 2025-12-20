// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExtsload} from "../interfaces/IExtsload.sol";

/// https://github.com/Uniswap/v4-core/blob/80311e34080fee64b6fc6c916e9a51a437d0e482/src/Exttload.sol
abstract contract Extsload is IExtsload {
    function extsload(uint256 slot) external view returns (uint256) {
        assembly ("memory-safe") {
            mstore(0, sload(slot))
            return(0, 0x20)
        }
    }

    function extsload(uint256 startSlot, uint256 nSlots) external view returns (uint256[] memory) {
        assembly ("memory-safe") {
            let memptr := mload(0x40)
            let start := memptr
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            let length := shl(5, nSlots)
            // The abi offset of dynamic array in the returndata is 32.
            mstore(memptr, 0x20)
            // Store the length of the array returned
            mstore(add(memptr, 0x20), nSlots)
            // update memptr to the first location to hold a result
            memptr := add(memptr, 0x40)
            let end := add(memptr, length)
            for {} 1 {} {
                mstore(memptr, sload(startSlot))
                memptr := add(memptr, 0x20)
                startSlot := add(startSlot, 1)
                if iszero(lt(memptr, end)) { break }
            }
            return(start, sub(end, start))
        }
    }

    function extsload(uint256[] calldata slots) external view returns (uint256[] memory) {
        assembly ("memory-safe") {
            let memptr := mload(0x40)
            let start := memptr
            // for abi encoding the response - the array will be found at 0x20
            mstore(memptr, 0x20)
            // next we store the length of the return array
            mstore(add(memptr, 0x20), slots.length)
            // update memptr to the first location to hold an array entry
            memptr := add(memptr, 0x40)
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            let end := add(memptr, shl(5, slots.length))
            let calldataptr := slots.offset
            for {} 1 {} {
                mstore(memptr, sload(calldataload(calldataptr)))
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            return(start, sub(end, start))
        }
    }
}
