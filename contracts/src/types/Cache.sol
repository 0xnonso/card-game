// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../helpers/Constants.sol";
import {GameData, GameStatus} from "../libraries/CardEngineLib.sol";
import {Card} from "./Card.sol";
import {PlayerStoreMap} from "./Map.sol";

type CacheValue is uint256;

using CacheManager for CacheValue global;
using {not_eq as !=, eq as ==} for CacheValue global;

function not_eq(CacheValue a, CacheValue b) pure returns (bool) {
    return CacheValue.unwrap(a) != CacheValue.unwrap(b);
}

function eq(CacheValue a, CacheValue b) pure returns (bool) {
    return CacheValue.unwrap(a) == CacheValue.unwrap(b);
}

library CacheManager {
    function toCachedValue(uint256 slot) internal view returns (CacheValue value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }

    function toStorage(CacheValue value, uint256 slot) internal {
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }

    function storeAddress(CacheValue value, uint8 ptr, address addr) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffffffffffffffffffffffffffffffffffffffff))), shl(ptr, addr))
        }
    }

    function loadAddress(CacheValue value, uint8 ptr) internal pure returns (address) {
        return address(uint160(CacheValue.unwrap(value) >> ptr));
    }

    function storeNibble(CacheValue value, uint8 ptr, uint8 nibble) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0x0f))), shl(ptr, and(nibble, 0x0f)))
        }
    }

    function loadNibble(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr) & 0x0f;
    }

    function storeU8(CacheValue value, uint8 ptr, uint8 _uint8) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xff))), shl(ptr, _uint8))
        }
    }

    function loadU8(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr);
    }

    function storeU16(CacheValue value, uint8 ptr, uint16 _uint16) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffff))), shl(ptr, _uint16))
        }
    }

    function loadU16(CacheValue value, uint8 ptr) internal pure returns (uint16) {
        return uint16(CacheValue.unwrap(value) >> ptr);
    }

    function storeU40(CacheValue value, uint8 ptr, uint40 _uint40) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, U40_MASK))), shl(ptr, _uint40))
        }
    }

    function loadU40(CacheValue value, uint8 ptr) internal pure returns (uint40) {
        return uint40(CacheValue.unwrap(value) >> ptr);
    }

    function storeU64(CacheValue value, uint8 ptr, uint64 _uint64) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, U64_MASK))), shl(ptr, _uint64))
        }
    }

    function loadU64(CacheValue value, uint8 ptr) internal pure returns (uint64) {
        return uint64(CacheValue.unwrap(value) >> ptr);
    }

    function loadU256(CacheValue value, uint8 ptr) internal pure returns (uint256) {
        return uint256(CacheValue.unwrap(value) >> ptr);
    }
}
