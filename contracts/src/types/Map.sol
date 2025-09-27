// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LibBit} from "solady/src/utils/LibBit.sol";

type DeckMap is uint64;
// deckMap, mapSize, len

// marketDeckMap - deckMap | card bit size | mapdata(in our case proposed player) | len - 6 bits

//
using DeckMapLib for DeckMap global;

library DeckMapLib {
    error IndexOutOfBounds();
    error IndexIsEmpty();
    error IndexNotEmpty();

    function rawMap(DeckMap deckMap) internal pure returns (uint56) {
        return uint56(DeckMap.unwrap(deckMap) >> 2);
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
        return DeckMap.unwrap(deckMap) & 0x3f;
    }

    function getDeckCardSize(DeckMap deckMap) internal pure returns (uint256) {
        return 8 - (deckMap.rawMap() & 0x03);
    }

    function getNonEmptyIdxs(DeckMap deckMap) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](deckMap.len());
        uint56 map = deckMap.rawMap();
        // console.log("deckMap: ", DeckMap.unwrap(deckMap) >> 8);

        uint256 currentIdx;
        while (map != 0) {
            uint256 firstSetBit = LibBit.ffs(uint256(map)); // find the first set bit
            // console.log("lsb", firstSetBit);
            unchecked {
                idxs[currentIdx++] = firstSetBit;
                map &= (map - 1);
            }
            // console.log("map idx", firstSetBit);
            // map = map - (uint56(1) << firstSetBit); // clear the first set bit
            // map = map >> (lsb + 1); // clear the first set bit
        }
        // gasEnd = gasleft();
        // console.log("gas_remain", gasBegin-gasEnd);
        return idxs;
    }

    function getNonEmptyIdxs(DeckMap deckMap, uint256 amount) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](amount);
        uint56 map = deckMap.rawMap();
        // console.log("deckMap: ", DeckMap.unwrap(deckMap) >> 10);

        // uint256 gasBegin = gasleft();
        uint256 currentIdx;
        while (map != 0) {
            if (amount == currentIdx) return idxs;

            uint256 firstSetBit = LibBit.ffs(map); // find the first set bit
            unchecked {
                idxs[currentIdx++] = firstSetBit;
                map &= (map - 1);
            }
            // map = map - uint56(1 << firstSetBit); // clear the first set bit
            // map = map >> (firstSetBit + 1); // clear the first set bit
        }

        // uint8[] memory idxs = new uint8[](amount);
        // uint256 currentIdx;
        // uint256 _deckMap = DeckMap.unwrap(deckMap) >> 10;
        // gasBegin = gasleft();
        // for (uint256 i = 0; _deckMap != 0; i++) {
        //     if (_deckMap & 1 != 0) {
        //         idxs[currentIdx++] = uint8(i);
        //         // console.log("setBitIdx_main", i);
        //     }
        //     _deckMap = _deckMap >> 1;
        //     if (amount == currentIdx) break;
        // }
        // gasEnd = gasleft();
        // console.log("gas_remain_0", gasBegin - gasEnd);

        return idxs;
    }

    function set(DeckMap deckMap, uint256 idx, bool empty) internal pure returns (DeckMap) {
        uint256 map = DeckMap.unwrap(deckMap);
        // assumes the usable bit-range fits before wrapping to uint56
        uint256 mask = uint256(1) << (idx + 2);
        // branchless: write bit = empty (0/1)
        map = (map & ~mask) | (uint256(empty ? 0 : 1) * mask);
        return DeckMap.wrap(uint56(map));
        // // if (idx > deckMap.len()) revert IndexOutOfBounds(); //revert("DeckMapLib: Idx out of bounds");
        // uint256 map = empty
        //     ? DeckMap.unwrap(deckMap) | (uint256(1) << (idx + 2))
        //     : DeckMap.unwrap(deckMap) & ~(uint256(1) << (idx + 2));
        // // uint256 mask = 1 << (idx + 10);
        // // uint256 map = DeckMap.unwrap(deckMap);
        // // int256 b;
        // // console.log("raw map1: ", rawMap);
        // // assembly {
        // //     rawMap := xor(map, and(xor(sub(empty, 1), map), mask))
        // // }
        // // console.log("raw map2: ", rawMap + 1);
        // // // b = -b;

        // // // assembly {
        // // //     map := xor(map, mask)
        // // // }
        // // // return map ^ (uint256(-b) ^ map) & mask;
        // return DeckMap.wrap(uint56(map));
        // // return DeckMap.wrap(uint64(map ^ (uint256(-b) ^ map) & mask));
    }

    function setToEmpty(DeckMap deckMap, uint256 idx) internal pure returns (DeckMap) {
        // set to empty with mask!
        // if(mask & deckmap != mask) revert("DeckMapLib: Idx not empty");
        // to  clear:
        // ~mask & deckmap
        if (deckMap.isEmpty(idx)) revert IndexIsEmpty(); //revert("DeckMapLib: Idx already empty");
        return deckMap.set(idx, false);
    }

    function setToEmpty(DeckMap deckMap, uint256[] memory idxs) internal pure returns (DeckMap) {
        // compute mask
        uint256 mask;
        uint256 map = uint256(deckMap.rawMap()); // get the map part
        uint256 idxsLen = idxs.length;
        for (uint256 i = 0; i < idxsLen; i++) {
            // if (idx[i] > 53) revert("DeckMapLib: Idx out of bounds");
            mask |= (uint256(1) << (idxs[i]));
        }
        // set to empty with mask!
        if (mask & map != mask) revert IndexIsEmpty(); //revert("DeckMapLib: Idx not empty");
        // to  clear:
        // uint64 deckMapLen = deckMap.len();
        return DeckMap.wrap(uint56((~mask & map) << 2 | (DeckMap.unwrap(deckMap) & 0x03)));
        // if (deckMap.isEmpty(idx)) revert("DeckMapLib: Idx already empty");
        // return deckMap.set(idx, false);
    }

    function fill(DeckMap deckMap, uint256[] memory idxs) internal pure returns (DeckMap) {
        // compute mask
        uint256 mask;
        uint256 map = uint256(deckMap.rawMap()); // get the map part
        uint256 idxsLen = idxs.length;
        for (uint256 i = 0; i < idxsLen; i++) {
            // if (idx[i] > 53) revert("DeckMapLib: Idx out of bounds");
            mask |= uint256(1) << idxs[i];
        }
        // set to filled with mask!
        if (mask & map != 0) revert IndexNotEmpty(); //("DeckMapLib: Idx already filled");
        return DeckMap.wrap(uint56(mask << 2 | DeckMap.unwrap(deckMap)));

        // if (deckMap.isNotEmpty(idx)) revert("DeckMapLib: Idx already filled");
        // return set(deckMap, idx, true);
    }

    function fill(DeckMap deckMap, uint256 idx) internal pure returns (DeckMap) {
        // set to filled with mask!
        // if(mask & deckMap != 0) revert("DeckMapLib: Idx already filled");
        if (deckMap.isNotEmpty(idx)) revert IndexNotEmpty(); //("DeckMapLib: Idx already filled");
        return set(deckMap, idx, true);
    }

    // instead of an array, give it a mask.
    // how to compute the mask?
    // function deal(DeckMap marketDeckMap, DeckMap playerDeckMap, uint256 mask)
    function deal(DeckMap marketDeckMap, DeckMap playerDeckMap, uint256[] memory idxs)
        internal
        pure
        returns (DeckMap, DeckMap)
    {
        // mask
        for (uint256 i = 0; i < idxs.length; i++) {
            marketDeckMap = marketDeckMap.setToEmpty(idxs[i]);
            playerDeckMap = playerDeckMap.fill(idxs[i]);
        }
        // marketDeckMap = marketDeckMap.setToEmpty(idxs);
        // playerDeckMap = playerDeckMap.fill(idxs);
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
        uint256 cardMask = (uint256(1) << cardBitsSize) - 1;
        for (uint256 i = 0; i < nonEmptyIdxs.length; i++) {
            // console.log("mask arr", nonEmptyIdxs[i]);
            uint256 idx = nonEmptyIdxs[i];
            mask[idx / numCardsIn0] |= cardMask << ((nonEmptyIdxs[i] % numCardsIn0) * cardBitsSize);
        }
    }
}

type PlayerStoreMap is uint8;
// playerStoreMap - uint8;

using PlayerStoreMapLib for PlayerStoreMap global;

// playerDeckMap - deckMap | proposedPlayer | mapdata(in our case proposed player) | len - 6 bits

library PlayerStoreMapLib {
    error IndexIsEmpty(uint256);
    error IndexNotEmpty(uint256);
    error MapIsEmpty(PlayerStoreMap);

    function rawMap(PlayerStoreMap playerStoreMap) internal pure returns (uint8) {
        return PlayerStoreMap.unwrap(playerStoreMap);
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

    function len(PlayerStoreMap playerStoreMap) internal pure returns (uint256) {
        return PlayerStoreMap.unwrap(playerStoreMap) & 0x0f;
    }

    function popCount(PlayerStoreMap playerStoreMap) internal pure returns (uint256 count) {
        assembly {
            let lo := and(playerStoreMap, 0x0f)
            let hi := shr(0x04, playerStoreMap)
            // forgefmt: disable-next-item
            count := add(
                    byte(lo, 0x0001010201020203010202030203030400000000000000000000000000000000),
                    byte(hi, 0x0001010201020203010202030203030400000000000000000000000000000000)
                )
        }
    }

    // function getNumProposedPlayers(PlayerStoreMap playerStoreMap) internal pure returns (uint8 num) {
    //     num = (playerStoreMap.rawMap() >> 4) & 0x0f;
    // }

    function getNonEmptyIdxs(PlayerStoreMap playerStoreMap) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](playerStoreMap.len());
        uint8 map = playerStoreMap.rawMap();
        uint256 currentIdx;
        while (map != 0) {
            uint8 lsb = map & uint8(~map + 1); // isolate LS1B without signed neg
            uint8 key = uint8(lsb * 0x1d) >> 5;
            uint256 nonEmptyIdx;
            assembly {
                map := xor(map, lsb)
                // forgefmt: disable-next-item
                nonEmptyIdx := byte(key, 0x0001060207050403000000000000000000000000000000000000000000000000)
            }
            idxs[currentIdx++] = nonEmptyIdx;
            // x ^= lsb; // clear that bit
        }
        // get the non-empty idxs in the player store map.
        // iterate through the map and get the non-empty idxs.
        // return the idxs as an array.
        return idxs;
    }

    function addPlayer(PlayerStoreMap map, uint256 idx) internal pure returns (PlayerStoreMap) {
        // add a player to the store map.
        // if the idx is already occupied, revert.
        if (map.isNotEmpty(idx)) {
            revert IndexNotEmpty(idx); //("PlayerStoreMapLib: Idx already occupied");
        }
        return PlayerStoreMap.wrap(uint8(map.rawMap() | (uint256(1) << idx)));
    }

    function removePlayer(PlayerStoreMap map, uint256 idx) internal pure returns (PlayerStoreMap) {
        // remove a player from the store map.
        // if the idx is already empty, revert.
        if (map.isEmpty(idx)) {
            revert IndexIsEmpty(idx); //("PlayerStoreMapLib: Idx already empty");
        }
        return PlayerStoreMap.wrap(uint8(map.rawMap() & ~(uint256(1) << idx)));
    }

    // function getActivePlayers(PlayerStoreMap playerStoreMap)
    //     internal
    //     view
    //     returns (uint256[] memory activePlayers)
    // {

    //     // return active players in the store map.
    //     // iterate through the map and get the active players.
    // }

    // function isActiveIndex(PlayerStoreMap playerStoreMap, uint256 idx)
    //     internal
    //     view
    //     returns (bool)
    // {
    //     // check if the idx is active in the store map.
    //     // if the idx is out of bounds, revert.
    //     // if (idx >= 16) {
    //     //     revert PlayerStoreMap_IndexOutOfBounds(); //("PlayerStoreMapLib: Idx out of bounds");
    //     // }
    //     return (PlayerStoreMap.unwrap(playerStoreMap) & (1 << idx)) != 0;
    // }

    // function isValidIndex(PlayerStoreMap playerStoreMap, uint256 idx) internal returns (bool) {}

    function getNextIndexFrom_RL(PlayerStoreMap playerStoreMap, uint8 startIdx) internal pure returns (uint8 nextIdx) {
        uint8 map = playerStoreMap.rawMap();
        if (map != 0) {
            uint8 shift = (startIdx + 1) & 0x07;
            uint8 rotate = (map >> shift) | (map << (8 - shift));
            // uint8 lsb = rotate & uint8(-rotate);
            uint8 key = ((rotate & uint8(~rotate + 1)) * 0x1d) >> 5;
            assembly {
                // forgefmt: disable-next-item
                let idx := byte(key, 0x0001060207050403000000000000000000000000000000000000000000000000)
                nextIdx := and(add(add(idx, startIdx), 0x01), 0x07)
            }
        } else {
            revert MapIsEmpty(playerStoreMap);
        }
    }

    // function getNextIndexFrom_LR(PlayerStoreMap playerStoreMap, uint256 startIdx)
    //     internal
    //     view
    //     returns (uint8 nextIdx)
    // {
    //     uint8 map = playerStoreMap.rawMap();
    // }
}
