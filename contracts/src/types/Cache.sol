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
    function toCachedValue(
        uint256 slot
    ) internal view returns (CacheValue value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }

    function toStorage(CacheValue value, uint256 slot) internal {
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }

    function storeAddress(
        CacheValue value,
        uint8 ptr,
        address addr
    ) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(
                and(
                    value,
                    not(shl(ptr, 0xffffffffffffffffffffffffffffffffffffffff))
                ),
                shl(ptr, addr)
            )
        }
    }

    function loadAddress(
        CacheValue value,
        uint8 ptr
    ) internal pure returns (address addr) {
        assembly {
            addr := and(shr(ptr, value), ADDRESS_MASK)
        }
        // return address(uint160(CacheValue.unwrap(value) >> ptr));
    }

    function storeNibble(
        CacheValue value,
        uint8 ptr,
        uint8 nibble
    ) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(
                and(value, not(shl(ptr, 0xf))),
                shl(ptr, and(nibble, 0xf))
            )
        }
    }

    function loadNibble(
        CacheValue value,
        uint8 ptr
    ) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr) & 0xf;
    }

    function storeU8(
        CacheValue value,
        uint8 ptr,
        uint8 _uint8
    ) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xff))), shl(ptr, _uint8))
        }
    }

    function loadU8(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr);
    }

    function storeU16(
        CacheValue value,
        uint8 ptr,
        uint16 _uint16
    ) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffff))), shl(ptr, _uint16))
        }
    }

    function loadU16(
        CacheValue value,
        uint8 ptr
    ) internal pure returns (uint16) {
        return uint16(CacheValue.unwrap(value) >> ptr);
    }

    function storeU40(
        CacheValue value,
        uint8 ptr,
        uint40 _uint40
    ) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(
                and(value, not(shl(ptr, U40_MASK))),
                shl(ptr, _uint40)
            )
        }
    }

    function loadU40(
        CacheValue value,
        uint8 ptr
    ) internal pure returns (uint40) {
        return uint40(CacheValue.unwrap(value) >> ptr);
    }

    function storeU64(
        CacheValue value,
        uint8 ptr,
        uint64 _uint64
    ) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(
                and(value, not(shl(ptr, U64_MASK))),
                shl(ptr, _uint64)
            )
        }
    }

    function loadU64(
        CacheValue value,
        uint8 ptr
    ) internal pure returns (uint64) {
        return uint64(CacheValue.unwrap(value) >> ptr);
    }

    function loadU256(
        CacheValue value,
        uint8 ptr
    ) internal pure returns (uint256) {
        return uint256(CacheValue.unwrap(value) >> ptr);
    }
}

import {IRuleset} from "../interfaces/IRuleSet.sol";
import {
    Action,
    CardEngineLib,
    GameData,
    GameStatus,
    PendingAction,
    PlayerData
} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {CacheManager, CacheValue} from "../types/Cache.sol";
import {Card, CardLib} from "../types/Card.sol";

import {HookPermissions} from "../types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";
import "hardhat/console.sol";

struct Cache {
    CacheValue prevValue;
    CacheValue value;
    uint256 slot;
}

library GameCacheManager {
    uint8 internal constant GAME_CREATOR_POS = 0;
    uint8 internal constant CALL_CARD_POS = 160;
    uint8 internal constant PLAYER_TURN_INDEX_POS = 168;
    uint8 internal constant STATUS_POS = 176;
    uint8 internal constant LAST_MOVE_TIMESTAMP_POS = 184;
    uint8 internal constant PLAYERS_LEFT_TO_JOIN_POS = 224;
    uint8 internal constant MAX_PLAYERS_POS = 228;
    uint8 internal constant NUM_PROPOSED_PLAYERS_POS = 232;
    uint8 internal constant HOOK_PERMISSIONS_POS = 236;
    uint8 internal constant PLAYER_STORE_MAP_POS = 248;

    uint8 internal constant RULESET_POS = 0;
    uint8 internal constant MARKET_DECK_MAP_POS = 160;
    uint8 internal constant INITIAL_HAND_SIZE_POS = 224;

    /// READ

    function ldCache(uint256 slot) internal view returns (Cache memory cache) {
        cache.slot = slot;
        cache.value = CacheManager.toCachedValue(slot);
        cache.prevValue = cache.value;
    }

    function ldGameCreator(Cache memory cache) internal pure returns (address) {
        return cache.value.loadAddress(GAME_CREATOR_POS);
    }

    function ldCallCard(Cache memory cache) internal pure returns (Card) {
        return Card.wrap(cache.value.loadU8(CALL_CARD_POS));
    }

    function ldPlayerTurnIndex(
        Cache memory cache
    ) internal pure returns (uint8) {
        return cache.value.loadU8(PLAYER_TURN_INDEX_POS);
    }

    function ldStatus(Cache memory cache) internal pure returns (GameStatus) {
        return GameStatus(cache.value.loadU8(STATUS_POS));
    }

    function ldLastMoveTimestamp(
        Cache memory cache
    ) internal pure returns (uint40) {
        return cache.value.loadU40(LAST_MOVE_TIMESTAMP_POS);
    }

    function ldPlayersLeftToJoin(
        Cache memory cache
    ) internal pure returns (uint8) {
        return cache.value.loadNibble(PLAYERS_LEFT_TO_JOIN_POS);
    }

    function ldMaxPlayers(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadNibble(MAX_PLAYERS_POS);
    }

    function ldNumProposedPlayers(
        Cache memory cache
    ) internal pure returns (uint8) {
        return cache.value.loadU8(NUM_PROPOSED_PLAYERS_POS);
    }

    function ldHandSize(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadU8(INITIAL_HAND_SIZE_POS);
    }

    function ldPlayerStoreMap(
        Cache memory cache
    ) internal pure returns (PlayerStoreMap) {
        return PlayerStoreMap.wrap(cache.value.loadU8(PLAYER_STORE_MAP_POS));
    }

    function ldRuleset(Cache memory cache) internal pure returns (IRuleset) {
        return IRuleset(cache.value.loadAddress(RULESET_POS));
    }

    function ldMarketDeckMap(
        Cache memory cache
    ) internal pure returns (DeckMap) {
        return DeckMap.wrap(cache.value.loadU64(MARKET_DECK_MAP_POS));
    }

    function ldHookPermissions(
        Cache memory cache
    ) internal pure returns (HookPermissions) {
        return HookPermissions.wrap(cache.value.loadU8(HOOK_PERMISSIONS_POS));
    }

    /// WRITE

    function sdGameCreator(
        Cache memory cache,
        address gameCreator
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeAddress(GAME_CREATOR_POS, gameCreator);
    }

    function sdCallCard(Cache memory cache, Card callCard) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(CALL_CARD_POS, Card.unwrap(callCard));
    }

    function sdPlayerTurnIndex(Cache memory cache, uint8 idx) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(PLAYER_TURN_INDEX_POS, idx);
    }

    function sdStatus(Cache memory cache, GameStatus status) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(STATUS_POS, uint8(status));
    }

    function sdLastMoveTimestamp(
        Cache memory cache,
        uint40 timestamp
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU40(LAST_MOVE_TIMESTAMP_POS, timestamp);
    }

    function sdPlayersLeftToJoin(
        Cache memory cache,
        uint8 playersLeft
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeNibble(PLAYERS_LEFT_TO_JOIN_POS, playersLeft);
    }

    function sdMaxPlayers(Cache memory cache, uint8 maxPlayers) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeNibble(MAX_PLAYERS_POS, maxPlayers);
    }

    function sdNumProposedPlayers(
        Cache memory cache,
        uint8 numProposedPlayers
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(
            NUM_PROPOSED_PLAYERS_POS,
            numProposedPlayers
        );
    }

    function sdHandSize(Cache memory cache, uint8 handSize) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(INITIAL_HAND_SIZE_POS, handSize);
    }

    function sdPlayerStoreMap(
        Cache memory cache,
        PlayerStoreMap playerStoreMap
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(
            PLAYER_STORE_MAP_POS,
            PlayerStoreMap.unwrap(playerStoreMap)
        );
    }

    function sdRuleset(Cache memory cache, IRuleset ruleset) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeAddress(RULESET_POS, address(ruleset));
    }

    function sdMarketDeckMap(
        Cache memory cache,
        DeckMap deckMap
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU64(
            MARKET_DECK_MAP_POS,
            DeckMap.unwrap(deckMap)
        );
    }

    function sdHookPermissions(
        Cache memory cache,
        HookPermissions permissions
    ) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(
            HOOK_PERMISSIONS_POS,
            HookPermissions.unwrap(permissions)
        );
    }

    function flush(Cache memory cache) internal {
        if (cache.value != cache.prevValue) {
            cache.value.toStorage(cache.slot);
            cache.prevValue = cache.value;
        }
    }
}
