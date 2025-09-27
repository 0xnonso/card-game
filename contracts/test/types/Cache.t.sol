// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../src/types/Cache.sol";
import "forge-std/Test.sol";

contract CacheManagerFuzzTest is Test {
    uint256 private constant BASE_SLOT = uint256(keccak256("forge.cache.manager.tests"));

    function writeSlot(uint256 slot, uint256 value) internal {
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }

    function readSlot(uint256 slot) internal view returns (uint256 value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }

    function clampPtr(uint8 ptr, uint8 byteLen) internal pure returns (uint8) {
        uint16 maxBitOffset = uint16(256) - uint16(byteLen) * 8;
        if (maxBitOffset == 0) return 0;
        return uint8(uint8(ptr) % uint8(maxBitOffset + 1));
    }

    function testFuzz_storeLoadU8(uint8 rawPtr, uint8 value, uint256 index) public {
        uint8 ptr = clampPtr(rawPtr, 1);
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeU8(ptr, value);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        uint8 got = loaded.loadU8(ptr);
        assertEq(got, value);
    }

    function testFuzz_storeLoadU16(uint8 rawPtr, uint16 value, uint256 index) public {
        uint8 ptr = clampPtr(rawPtr, 2);
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeU16(ptr, value);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        uint16 got = loaded.loadU16(ptr);
        assertEq(got, value);
    }

    function testFuzz_storeLoadNibble(uint8 rawPtr, uint8 nibble, uint256 index) public {
        nibble = nibble & 0x0f;
        uint8 ptr = clampPtr(rawPtr, 0);
        if (ptr > 252) ptr = ptr % 253;
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeNibble(ptr, nibble);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        uint8 got = loaded.loadNibble(ptr);
        assertEq(got, nibble);
    }

    function testFuzz_storeLoadAddress(uint8 rawPtr, address addr, uint256 index) public {
        uint8 ptr = clampPtr(rawPtr, 20);
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeAddress(ptr, addr);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        address got = loaded.loadAddress(ptr);
        assertEq(got, addr);
    }

    function testFuzz_storeLoadU40(uint8 rawPtr, uint40 value, uint256 index) public {
        uint8 ptr = clampPtr(rawPtr, 5);
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeU40(ptr, value);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        uint40 got = loaded.loadU40(ptr);
        assertEq(uint256(got), uint256(value));
    }

    function testFuzz_storeLoadU64(uint8 rawPtr, uint64 value, uint256 index) public {
        uint8 ptr = clampPtr(rawPtr, 8);
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeU64(ptr, value);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        uint64 got = loaded.loadU64(ptr);
        assertEq(uint256(got), uint256(value));
    }

    function testFuzz_storeLoadU256(uint8 rawPtr, uint256 value, uint256 index) public {
        uint8 ptr = clampPtr(rawPtr, 32);
        uint256 slot = BASE_SLOT + (index % 256);
        writeSlot(slot, 0);

        CacheValue v = CacheManager.toCachedValue(slot);
        CacheValue updated = v.storeU256(ptr, value);
        CacheManager.toStorage(updated, slot);

        CacheValue loaded = CacheManager.toCachedValue(slot);
        uint256 got = loaded.loadU256(ptr);
        assertEq(got, value);
    }

    function testFuzz_toCachedValueToStorage(uint256 rawValue, uint256 index) public {
        uint256 slot = BASE_SLOT + (index % 1024);
        writeSlot(slot, rawValue);
        CacheValue v = CacheManager.toCachedValue(slot);

        uint256 readBack = v.loadU256(0);
        assertEq(readBack, rawValue);

        CacheValue modified = v.storeU8(16, uint8(0xAB));
        CacheManager.toStorage(modified, slot);
        CacheValue v2 = CacheManager.toCachedValue(slot);
        assertEq(v2.loadU8(16), uint8(0xAB));
    }
}
