// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LibBit} from "solady/src/utils/LibBit.sol";

type WhotDeckMap is uint64;
// deckMap, mapSize, len

// marketDeckMap - deckMap | card bit size | mapdata(in our case proposed player) | len - 6 bits

using WhotDeckMapLib for WhotDeckMap global;

library WhotDeckMapLib {
    error IndexOutOfBounds();
    error IndexIsEmpty();
    error IndexNotEmpty();

    function rawMap(WhotDeckMap deckMap) internal pure returns (uint56) {
        return uint56(WhotDeckMap.unwrap(deckMap) >> 8);
    }

    function isEmpty(WhotDeckMap deckMap, uint256 idx) internal pure returns (bool) {
        return WhotDeckMap.unwrap(deckMap) & (uint256(1) << (idx + 8)) == 0;
    }

    function isNotEmpty(WhotDeckMap deckMap, uint256 idx) internal pure returns (bool) {
        return WhotDeckMap.unwrap(deckMap) & (uint256(1) << (idx + 8)) != 0;
    }

    function isMapEmpty(WhotDeckMap deckMap) internal pure returns (bool _isEmpty) {
        assembly {
            _isEmpty := iszero(and(deckMap, not(0xC0)))
        }
    }

    function isMapNotEmpty(WhotDeckMap deckMap) internal pure returns (bool _isNotEmpty) {
        assembly {
            _isNotEmpty := iszero(iszero(and(deckMap, not(0xC0))))
        }
    }

    function len(WhotDeckMap deckMap) internal pure returns (uint256) {
        return WhotDeckMap.unwrap(deckMap) & 0x3f;
    }

    function getDeckCardSize(WhotDeckMap deckMap) internal pure returns (uint256) {
        return 8 - ((WhotDeckMap.unwrap(deckMap) >> 6) & 0x03);
    }

    function getNonEmptyIdxs(WhotDeckMap deckMap) internal pure returns (uint256[] memory) {
        uint256[] memory idxs = new uint256[](deckMap.len());
        uint56 map = deckMap.rawMap();
        // console.log("deckMap: ", WhotDeckMap.unwrap(deckMap) >> 8);

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

    function getNonEmptyIdxs(WhotDeckMap deckMap, uint256 amount)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory idxs = new uint256[](amount);
        uint56 map = deckMap.rawMap();
        // console.log("deckMap: ", WhotDeckMap.unwrap(deckMap) >> 10);

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
        // uint256 _deckMap = WhotDeckMap.unwrap(deckMap) >> 10;
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

    function set(WhotDeckMap deckMap, uint256 idx, bool empty)
        internal
        pure
        returns (WhotDeckMap)
    {
        // if (idx > deckMap.len()) revert IndexOutOfBounds(); //revert("WhotDeckMapLib: Idx out of bounds");
        uint256 map = empty
            ? (WhotDeckMap.unwrap(deckMap) + 1) | (uint256(1) << (idx + 8))
            : (WhotDeckMap.unwrap(deckMap) - 1) & ~(uint256(1) << (idx + 8));
        // uint256 mask = 1 << (idx + 10);
        // uint256 map = WhotDeckMap.unwrap(deckMap);
        // int256 b;
        // console.log("raw map1: ", rawMap);
        // assembly {
        //     rawMap := xor(map, and(xor(sub(empty, 1), map), mask))
        // }
        // console.log("raw map2: ", rawMap + 1);
        // // b = -b;

        // // assembly {
        // //     map := xor(map, mask)
        // // }
        // // return map ^ (uint256(-b) ^ map) & mask;
        return WhotDeckMap.wrap(uint64(map));
        // return WhotDeckMap.wrap(uint64(map ^ (uint256(-b) ^ map) & mask));
    }

    function setToEmpty(WhotDeckMap deckMap, uint256 idx) internal pure returns (WhotDeckMap) {
        // set to empty with mask!
        // if(mask & deckmap != mask) revert("WhotDeckMapLib: Idx not empty");
        // to  clear:
        // ~mask & deckmap
        if (deckMap.isEmpty(idx)) revert IndexIsEmpty(); //revert("WhotDeckMapLib: Idx already empty");
        return deckMap.set(idx, false);
    }

    function setToEmpty(WhotDeckMap deckMap, uint256[] memory idxs)
        internal
        pure
        returns (WhotDeckMap)
    {
        // compute mask
        uint256 mask;
        uint256 map = uint256(deckMap.rawMap()); // get the map part
        uint256 idxsLen = idxs.length;
        for (uint256 i = 0; i < idxsLen; i++) {
            // if (idx[i] > 53) revert("WhotDeckMapLib: Idx out of bounds");
            mask |= (uint256(1) << (idxs[i]));
        }
        // set to empty with mask!
        if (mask & map != mask) revert IndexIsEmpty(); //revert("WhotDeckMapLib: Idx not empty");
        // to  clear:
        // uint64 deckMapLen = deckMap.len();
        return WhotDeckMap.wrap(uint64((~mask & map) << 8 | deckMap.len() - idxsLen));
        // if (deckMap.isEmpty(idx)) revert("WhotDeckMapLib: Idx already empty");
        // return deckMap.set(idx, false);
    }

    function fill(WhotDeckMap deckMap, uint256[] memory idxs) internal pure returns (WhotDeckMap) {
        // compute mask
        uint256 mask;
        uint256 map = uint256(deckMap.rawMap()); // get the map part
        uint256 idxsLen = idxs.length;
        for (uint256 i = 0; i < idxsLen; i++) {
            // if (idx[i] > 53) revert("WhotDeckMapLib: Idx out of bounds");
            mask |= uint256(1) << idxs[i];
        }
        // set to filled with mask!
        if (mask & map != 0) revert IndexNotEmpty(); //("WhotDeckMapLib: Idx already filled");
        return WhotDeckMap.wrap(uint64((mask | map) << 8 | (deckMap.len() + idxsLen)));

        // if (deckMap.isNotEmpty(idx)) revert("WhotDeckMapLib: Idx already filled");
        // return set(deckMap, idx, true);
    }

    function fill(WhotDeckMap deckMap, uint256 idx) internal pure returns (WhotDeckMap) {
        // set to filled with mask!
        // if(mask & deckMap != 0) revert("WhotDeckMapLib: Idx already filled");
        if (deckMap.isNotEmpty(idx)) revert IndexNotEmpty(); //("WhotDeckMapLib: Idx already filled");
        return set(deckMap, idx, true);
    }

    // instead of an array, give it a mask.
    // how to compute the mask?
    // function deal(WhotDeckMap marketDeckMap, WhotDeckMap playerDeckMap, uint256 mask)
    function deal(WhotDeckMap marketDeckMap, WhotDeckMap playerDeckMap, uint256[] memory idxs)
        internal
        pure
        returns (WhotDeckMap, WhotDeckMap)
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

    function deal(WhotDeckMap marketDeckMap, WhotDeckMap playerDeckMap)
        internal
        pure
        returns (WhotDeckMap, WhotDeckMap, uint256)
    {
        uint256 idx = marketDeckMap.getNonEmptyIdxs(1)[0];

        marketDeckMap = marketDeckMap.setToEmpty(idx);
        playerDeckMap = playerDeckMap.fill(idx);

        return (marketDeckMap, playerDeckMap, idx);
    }

    function computeMask(WhotDeckMap deckMap) internal pure returns (uint256[2] memory mask) {
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

type PlayerStoreMap is uint16;

using PlayerStoreMapLib for PlayerStoreMap global;

// playerDeckMap - deckMap | proposedPlayer | mapdata(in our case proposed player) | len - 6 bits

library PlayerStoreMapLib {
    error IndexIsEmpty(uint256);
    error IndexNotEmpty(uint256);
    error MapIsEmpty(PlayerStoreMap);

    function isEmpty(PlayerStoreMap playerStoreMap, uint256 idx) internal pure returns (bool) {
        return (PlayerStoreMap.unwrap(playerStoreMap) & (uint256(1) << (idx + 8))) == 0;
    }

    function isNotEmpty(PlayerStoreMap playerStoreMap, uint256 idx) internal pure returns (bool) {
        return (PlayerStoreMap.unwrap(playerStoreMap) & (uint256(1) << (idx + 8))) != 0;
    }

    function isMapEmpty(PlayerStoreMap playerStoreMap) internal pure returns (bool) {
        return PlayerStoreMap.unwrap(playerStoreMap) == 0;
    }

    function isMapNotEmpty(PlayerStoreMap playerStoreMap) internal pure returns (bool) {
        return PlayerStoreMap.unwrap(playerStoreMap) != 0;
    }

    function len(PlayerStoreMap playerStoreMap) internal pure returns (uint256) {
        return PlayerStoreMap.unwrap(playerStoreMap) & 0x0f;
    }

    function rawMap(PlayerStoreMap playerStoreMap) internal pure returns (uint8) {
        return uint8(PlayerStoreMap.unwrap(playerStoreMap) >> 8);
    }

    function popCount(PlayerStoreMap playerStoreMap) internal pure returns (uint256 count) {
        uint8 map = playerStoreMap.rawMap();
        assembly {
            let lo := and(map, 0x0f)
            let hi := shr(0x04, map)
            // forgefmt: disable-next-item
            count := add(
                    byte(lo, 0x0001010201020203010202030203030400000000000000000000000000000000),
                    byte(hi, 0x0001010201020203010202030203030400000000000000000000000000000000)
                )
        }
    }

    function getNumProposedPlayers(PlayerStoreMap playerStoreMap)
        internal
        pure
        returns (uint8 num)
    {
        num = (playerStoreMap.rawMap() >> 4) & 0x0f;
    }

    function getNonEmptyIdxs(PlayerStoreMap playerStoreMap)
        internal
        pure
        returns (uint256[] memory)
    {
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
        return PlayerStoreMap.wrap(uint16((PlayerStoreMap.unwrap(map) + 1) | (uint256(1) << idx)));
    }

    function removePlayer(PlayerStoreMap map, uint256 idx) internal pure returns (PlayerStoreMap) {
        // remove a player from the store map.
        // if the idx is already empty, revert.
        if (map.isEmpty(idx)) {
            revert IndexIsEmpty(idx); //("PlayerStoreMapLib: Idx already empty");
        }
        return PlayerStoreMap.wrap(uint16((PlayerStoreMap.unwrap(map) - 1) & ~(uint256(1) << idx)));
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

    function getNextIndexFrom_RL(PlayerStoreMap playerStoreMap, uint8 startIdx)
        internal
        pure
        returns (uint8 nextIdx)
    {
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
