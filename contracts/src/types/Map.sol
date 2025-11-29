// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import "hardhat/console.sol";
import {LibBit} from "solady/src/utils/LibBit.sol";

type DeckMap is uint64;

using DeckMapLib for DeckMap global;

library DeckMapLib {
    error IndexOutOfBounds();
    error IndexIsEmpty();
    error IndexNotEmpty();

    function rawMap(DeckMap deckMap) internal pure returns (uint64) {
        return uint64(DeckMap.unwrap(deckMap) >> 2);
    }

    function newMap(DeckMap deckMap) internal pure returns (DeckMap) {
        return DeckMap.wrap(DeckMap.unwrap(deckMap) & 0x03);
    }

    function isEmpty(DeckMap deckMap, uint256 idx) internal pure returns (bool) {
        return deckMap.rawMap() & (uint256(1) << idx) == 0;
    }

    function isNotEmpty(DeckMap deckMap, uint256 idx) internal pure returns (bool) {
        return deckMap.rawMap() & (uint256(1) << idx) != 0;
    }

    function isMapEmpty(DeckMap deckMap) internal pure returns (bool) {
        return deckMap.rawMap() == 0;
    }

    function isMapNotEmpty(DeckMap deckMap) internal pure returns (bool) {
        return deckMap.rawMap() != 0;
    }

    function len(DeckMap deckMap) internal pure returns (uint256) {
        return LibBit.popCount(uint256(deckMap.rawMap()));
    }

    function getDeckCardSize(DeckMap deckMap) internal pure returns (uint256) {
        return 8 - (DeckMap.unwrap(deckMap) & 0x03);
    }

    function getNonEmptyIdxs(DeckMap deckMap) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](deckMap.len());
        uint64 map = deckMap.rawMap();

        uint256 currentIdx;
        while (map != 0) {
            uint256 firstSetBit = LibBit.ffs(uint256(map)); // find the first set bit
            unchecked {
                idxs[currentIdx++] = firstSetBit;
                map &= (map - 1);
            }
        }

        return idxs;
    }

    function getNonEmptyIdxs(DeckMap deckMap, uint256 amount) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](amount);
        uint64 map = deckMap.rawMap();
        uint256 currentIdx;
        while (map != 0) {
            if (amount == currentIdx) return idxs;
            uint256 firstSetBit = LibBit.ffs(map); // find the first set bit
            unchecked {
                idxs[currentIdx++] = firstSetBit;
                map &= (map - 1);
            }
        }
        return idxs;
    }

    function set(DeckMap deckMap, uint256 idx, bool empty) internal pure returns (DeckMap) {
        uint256 map = empty
            ? DeckMap.unwrap(deckMap) | (uint256(1) << (idx + 2))
            : DeckMap.unwrap(deckMap) & ~(uint256(1) << (idx + 2));
        return DeckMap.wrap(uint64(map));
    }

    function setToEmpty(DeckMap deckMap, uint256 idx) internal pure returns (DeckMap) {
        if (deckMap.isEmpty(idx)) revert IndexIsEmpty();
        return deckMap.set(idx, false);
    }

    function setToEmpty(DeckMap deckMap, uint256[] memory idxs) internal pure returns (DeckMap) {
        // compute mask
        uint256 mask;
        uint256 map = uint256(deckMap.rawMap()); // get the map part
        uint256 idxsLen = idxs.length;
        for (uint256 i = 0; i < idxsLen; i++) {
            mask |= (uint256(1) << (idxs[i]));
        }
        if (mask & map != mask) revert IndexIsEmpty();
        return DeckMap.wrap(uint64((~mask & map) << 2 | (DeckMap.unwrap(deckMap) & 0x03)));
    }

    function fill(DeckMap deckMap, uint256[] memory idxs) internal pure returns (DeckMap) {
        // compute mask
        uint256 mask;
        uint256 map = uint256(deckMap.rawMap()); // get the map part
        uint256 idxsLen = idxs.length;
        for (uint256 i = 0; i < idxsLen; i++) {
            mask |= uint256(1) << idxs[i];
        }
        if (mask & map != 0) revert IndexNotEmpty();
        return DeckMap.wrap(uint64(mask << 2 | DeckMap.unwrap(deckMap)));
    }

    function fill(DeckMap deckMap, uint256 idx) internal pure returns (DeckMap) {
        if (deckMap.isNotEmpty(idx)) revert IndexNotEmpty();
        return set(deckMap, idx, true);
    }

    function deal(DeckMap marketDeckMap, DeckMap playerDeckMap, uint256[] memory idxs)
        internal
        pure
        returns (DeckMap, DeckMap)
    {
        marketDeckMap = marketDeckMap.setToEmpty(idxs);
        playerDeckMap = playerDeckMap.fill(idxs);
        return (marketDeckMap, playerDeckMap);
    }

    function deal(DeckMap marketDeckMap, DeckMap playerDeckMap) internal pure returns (DeckMap, DeckMap, uint256) {
        uint256 idx = marketDeckMap.getNonEmptyIdxs(1)[0];

        marketDeckMap = marketDeckMap.setToEmpty(idx);
        playerDeckMap = playerDeckMap.fill(idx);

        return (marketDeckMap, playerDeckMap, idx);
    }

    function computeMask(DeckMap deckMap) internal pure returns (uint256[2] memory mask) {
        uint256[] memory nonEmptyIdxs = deckMap.getNonEmptyIdxs();
        uint256 cardBitsSize = deckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardBitsSize;
        uint256 cardMask = (uint256(1) << (cardBitsSize)) - 1;
        for (uint256 i = 0; i < nonEmptyIdxs.length; i++) {
            uint256 idx = nonEmptyIdxs[i];
            mask[idx / numCardsIn0] = mask[idx / numCardsIn0] | (cardMask << ((idx % numCardsIn0) * cardBitsSize));
        }
    }
}

type PlayerStoreMap is uint16;

using PlayerStoreMapLib for PlayerStoreMap global;

library PlayerStoreMapLib {
    error IndexIsEmpty(uint256);
    error IndexNotEmpty(uint256);
    error MapIsEmpty(PlayerStoreMap);

    function rawMap(PlayerStoreMap playerStoreMap) internal pure returns (uint16) {
        return PlayerStoreMap.unwrap(playerStoreMap) >> 1;
    }

    function isEmpty(PlayerStoreMap playerStoreMap, uint256 idx) internal pure returns (bool) {
        return playerStoreMap.rawMap() & (uint256(1) << idx) == 0;
    }

    function isNotEmpty(PlayerStoreMap playerStoreMap, uint256 idx) internal pure returns (bool) {
        return playerStoreMap.rawMap() & (uint256(1) << (idx)) != 0;
    }

    function isMapEmpty(PlayerStoreMap playerStoreMap) internal pure returns (bool) {
        return playerStoreMap.rawMap() == 0;
    }

    function isMapNotEmpty(PlayerStoreMap playerStoreMap) internal pure returns (bool) {
        return playerStoreMap.rawMap() != 0;
    }

    function direction(PlayerStoreMap playerStoreMap) internal pure returns (uint8) {
        return uint8(PlayerStoreMap.unwrap(playerStoreMap) & 1);
    }

    function len(PlayerStoreMap playerStoreMap) internal pure returns (uint256 count) {
        uint16 map = playerStoreMap.rawMap();
        assembly {
            map := sub(map, and(shr(1, map), 0x5555))
            map := add(and(map, 0x3333), and(shr(2, map), 0x3333))
            map := and(add(map, shr(4, map)), 0x0f0f)
            count := shr(8, mul(map, 0x0101))
        }
    }

    function getNonEmptyIdxs(PlayerStoreMap playerStoreMap) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](playerStoreMap.len());
        uint16 map = playerStoreMap.rawMap();
        uint256 currentIdx;

        while (map != 0) {
            uint16 lsb = map & (~map + 1);
            uint8 key = uint8(((lsb * 0x09AF) & 0xFFFF) >> 12);
            uint256 nonEmptyIdx;
            assembly {
                map := xor(map, lsb)
                nonEmptyIdx := byte(key, 0x000102050309060b0f04080a0e070d0c00000000000000000000000000000000)
            }
            idxs[currentIdx++] = nonEmptyIdx;
        }

        return idxs;
    }

    function addPlayer(PlayerStoreMap map, uint256 idx) internal pure returns (PlayerStoreMap) {
        if (map.isNotEmpty(idx)) {
            revert IndexNotEmpty(idx);
        }
        return PlayerStoreMap.wrap(uint16(PlayerStoreMap.unwrap(map) | (uint256(1) << (idx + 1))));
    }

    function removePlayer(PlayerStoreMap map, uint256 idx) internal pure returns (PlayerStoreMap) {
        if (map.isEmpty(idx)) {
            revert IndexIsEmpty(idx);
        }
        return PlayerStoreMap.wrap(uint16(PlayerStoreMap.unwrap(map) & ~(uint256(1) << (idx + 1))));
    }

    function toggleDirection(PlayerStoreMap playerStoreMap) internal pure returns (PlayerStoreMap) {
        return PlayerStoreMap.wrap(PlayerStoreMap.unwrap(playerStoreMap) & 254 | (1 - playerStoreMap.direction()));
    }

    function getNextIndex(PlayerStoreMap playerStoreMap, uint8 startIdx) internal pure returns (uint8 nextIdx) {
        uint16 map = playerStoreMap.rawMap();
        if (map == 0) revert MapIsEmpty(playerStoreMap);

        bool leftToRight = playerStoreMap.direction() != 0;
        uint16 bit;

        if (!leftToRight) {
            uint16 forwardMask = uint16(~((uint32(1) << (startIdx + 1)) - 1)) & 0xFFFF;
            uint16 forwardBits = map & forwardMask;
            uint16 wrapBits = map & ~forwardMask;
            uint16 candidates = forwardBits != 0 ? forwardBits : wrapBits;
            bit = candidates & (~candidates + 1);
        } else {
            uint16 backwardMask = uint16((uint32(1) << startIdx) - 1);
            uint16 backwardBits = map & backwardMask; // bits < s
            uint16 candidates = backwardBits != 0 ? backwardBits : map;
            uint16 x = candidates;
            x |= x >> 1;
            x |= x >> 2;
            x |= x >> 4;
            x |= x >> 8;
            bit = x & ~uint16(x >> 1);
        }

        // De Bruijn: bit → index 0..15
        assembly {
            // key = ((bit * 0x077CB531) >> 27) & 31
            let key := and(shr(27, mul(bit, 0x077CB531)), 31)

            // LUT (32 bytes) for LS1B index:
            // [0,1,28,2,29,14,24,3,
            //  30,22,20,15,25,17,4,8,
            //  31,27,13,23,21,19,16,7,
            //  26,12,18,6,11,5,10,9]
            let lut := 0x00011c021d0e18031e16140f191104081f1b0d17151310071a0c12060b050a09

            nextIdx := byte(key, lut)
        }
    }
}
