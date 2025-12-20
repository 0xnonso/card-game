// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../src/types/Map.sol";
import "../helpers/BitLookupTable.sol";
import "forge-std/Test.sol";

contract MapTest is Test {
    function test_fuzz_DeckMap_Length(uint64 rawDeckMap) public {
        DeckMap deckMap = DeckMap.wrap(rawDeckMap);
        assertEq(deckMap.rawMap(), uint64(rawDeckMap >> 2));
        assertEq(deckMap.len(), BitLookupTable.popcount(deckMap.rawMap()));
    }

    function test_fuzz_PlayerStoreMap_Length(uint16 rawPlayerStoreMap) public {
        PlayerStoreMap playerStoreMap = PlayerStoreMap.wrap(rawPlayerStoreMap);
        assertEq(playerStoreMap.rawMap(), uint16(rawPlayerStoreMap >> 1));
        assertEq(playerStoreMap.len(), BitLookupTable.popcount(playerStoreMap.rawMap()));
    }

    function test_fuzz_PlayerStoreMap_GetNextIndex(uint16 rawPlayerStoreMap, uint8 startIdx) public {
        uint8 dir;
        assembly {
            dir := and(rawPlayerStoreMap, 0x1)
        }
        startIdx = uint8(bound(startIdx, 0, 15));
        PlayerStoreMap playerStoreMap = PlayerStoreMap.wrap(rawPlayerStoreMap);
        vm.assume(BitLookupTable.popcount(playerStoreMap.rawMap()) > 1);
        assertEq(playerStoreMap.direction(), dir);
        uint8 nextIdx = playerStoreMap.getNextIndex(startIdx);
        if (dir != 0) {
            assertEq(nextIdx, BitLookupTable.nextRight(playerStoreMap.rawMap(), startIdx));
        } else {
            assertEq(nextIdx, BitLookupTable.nextLeft(playerStoreMap.rawMap(), startIdx));
        }
    }

    function test_fuzz_DeckMap_GetNonEmptyIdxs(uint64 rawDeckMap) public {
        DeckMap deckMap = DeckMap.wrap(rawDeckMap);
        uint256[] memory idxs = deckMap.getNonEmptyIdxs();
        uint256 expectedLen = deckMap.len();
        assertEq(idxs.length, expectedLen);
        assertEq(idxs.length, BitLookupTable.popcount(deckMap.rawMap()));
        for (uint256 i = 0; i < idxs.length; i++) {
            assertTrue(deckMap.isNotEmpty(idxs[i]));
        }
    }

    function fuzz_PlayerStoreMap_GetNonEmptyIdxs(uint16 rawPlayerStoreMap) public {
        PlayerStoreMap playerStoreMap = PlayerStoreMap.wrap(rawPlayerStoreMap);
        uint256[] memory idxs = playerStoreMap.getNonEmptyIdxs();
        uint256 expectedLen = playerStoreMap.len();
        assertEq(idxs.length, expectedLen);
        assertEq(idxs.length, BitLookupTable.popcount(playerStoreMap.rawMap()));
        for (uint256 i = 0; i < idxs.length; i++) {
            assertTrue(playerStoreMap.isNotEmpty(idxs[i]));
        }
    }

    function test_fuzz_DeckMap_Deal_Random(uint8 index) public {
        DeckMap marketDeckMap = DeckMap.wrap(0xffffffffffffffff);
        DeckMap playerDeckMap = DeckMap.wrap(0);
        index = uint8(bound(index, 0, 61));
        uint256[] memory idxs = new uint256[](1);
        idxs[0] = uint256(index);
        assertTrue(playerDeckMap.isEmpty(index));
        assertTrue(marketDeckMap.isNotEmpty(index));
        (marketDeckMap, playerDeckMap) = marketDeckMap.deal(playerDeckMap, idxs);
        assertTrue(playerDeckMap.isNotEmpty(index));
        assertTrue(marketDeckMap.isEmpty(index));
    }
}
