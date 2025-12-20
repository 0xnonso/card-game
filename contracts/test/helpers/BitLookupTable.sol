// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BitLookupTable {
    uint8 internal constant NO_BIT = 0xFF;

    function _popcount(uint8 x) internal view returns (uint8) {
        // forgefmt: disable-next-item
        uint8[256] memory POPCOUNT8 = [
            0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4, 
            1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
            1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 
            2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
            1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 
            2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
            2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 
            3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
            1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5, 
            2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
            2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 
            3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
            2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6, 
            3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
            3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7, 
            4, 5, 5, 6, 5, 6, 6, 7, 5, 6, 6, 7, 6, 7, 7, 8
        ];
        return POPCOUNT8[x];
    }

    function popcount(uint8 x) internal view returns (uint8) {
        return _popcount(x);
    }

    function popcount(uint64 x) internal view returns (uint8) {
        // forgefmt: disable-next-item
        return _popcount(uint8(x)) 
            + _popcount(uint8(x >> 8)) 
            + _popcount(uint8(x >> 16))
            + _popcount(uint8(x >> 24)) 
            + _popcount(uint8(x >> 32)) 
            + _popcount(uint8(x >> 40))
            + _popcount(uint8(x >> 48)) 
            + _popcount(uint8(x >> 56));
    }

    function nextRight(uint64 value, uint8 startIdx) internal pure returns (uint8 next) {
        uint256 i = (startIdx + 63) % 64;
        next = NO_BIT;
        while (i != startIdx) {
            if ((value & (1 << i)) != 0) {
                next = uint8(i);
                break;
            }
            i = (i + 63) % 64;
        }
    }

    function nextLeft(uint64 value, uint8 startIdx) internal pure returns (uint8 next) {
        uint256 i = (uint256(startIdx) + 1) % 64;
        next = NO_BIT;
        while (i != startIdx) {
            if ((value & (1 << i)) != 0) {
                next = uint8(i);
                break;
            }
            i = (i + 1) % 64;
        }
    }
}
