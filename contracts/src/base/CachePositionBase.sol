// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action, CardEngineLib, GameData, GameStatus, PendingAction, PlayerData} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {CacheManager, CacheValue} from "../types/Cache.sol";
import {Card, CardLib} from "../types/Card.sol";

import {HookPermissions} from "../types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";

abstract contract CachePositionBase {
    uint8 constant GAME_CREATOR_POS = 0;
    uint8 constant CALL_CARD_POS = 160;
    uint8 constant PLAYER_TURN_INDEX_POS = 168;
    uint8 constant STATUS_POS = 176;
    uint8 constant LAST_MOVE_TIMESTAMP_POS = 184;
    uint8 constant PLAYERS_LEFT_TO_JOIN_POS = 224;
    uint8 constant MAX_PLAYERS_POS = 228;
    uint8 constant NUM_PROPOSED_PLAYERS_POS = 232;
    uint8 constant HOOK_PERMISSIONS_POS = 240;
    uint8 constant PLAYER_STORE_MAP_POS = 248;

    uint8 constant RULESET_POS = 0;
    uint8 constant MARKET_DECK_MAP_POS = 160;
    uint8 constant INITIAL_HAND_SIZE_POS = 168;

    struct Cache {
        CacheValue value;
        uint256 slot;
    }

    /// READ

    function loadCache(GameData storage game, uint256 indexFrom) internal view returns (Cache memory cache) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := add(game.slot, indexFrom)
        }
        cache.slot = slot;
        cache.value = CacheManager.toCachedValue(slot);
    }

    function loadGameCreator(Cache memory cache) internal pure returns (address) {
        return cache.value.loadAddress(GAME_CREATOR_POS);
    }

    function loadCallCard(Cache memory cache) internal pure returns (Card) {
        return Card.wrap(cache.value.loadU8(CALL_CARD_POS));
    }

    function loadPlayerTurnIndex(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadU8(PLAYER_TURN_INDEX_POS);
    }

    function loadStatus(Cache memory cache) internal pure returns (GameStatus) {
        return GameStatus(cache.value.loadU8(STATUS_POS));
    }

    function loadLastMoveTimestamp(Cache memory cache) internal pure returns (uint40) {
        return cache.value.loadU40(LAST_MOVE_TIMESTAMP_POS);
    }

    function loadPlayersLeftToJoin(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadNibble(PLAYERS_LEFT_TO_JOIN_POS);
    }

    function loadMaxPlayers(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadNibble(MAX_PLAYERS_POS);
    }

    function loadNumProposedPlayers(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadU8(NUM_PROPOSED_PLAYERS_POS);
    }

    function loadHandSize(Cache memory cache) internal pure returns (uint8) {
        return cache.value.loadU8(INITIAL_HAND_SIZE_POS);
    }

    function loadPlayerStoreMap(Cache memory cache) internal pure returns (PlayerStoreMap) {
        return PlayerStoreMap.wrap(cache.value.loadU8(PLAYER_STORE_MAP_POS));
    }

    function loadRuleset(Cache memory cache) internal pure returns (IRuleset) {
        return IRuleset(cache.value.loadAddress(RULESET_POS));
    }

    function loadMarketDeckMap(Cache memory cache) internal pure returns (DeckMap) {
        return DeckMap.wrap(cache.value.loadU64(MARKET_DECK_MAP_POS));
    }

    function loadHookPermissions(Cache memory cache) internal pure returns (HookPermissions) {
        return HookPermissions.wrap(cache.value.loadU8(HOOK_PERMISSIONS_POS));
    }

    /// WRITE

    function storeGameCreator(Cache memory cache, address gameCreator) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeAddress(GAME_CREATOR_POS, gameCreator);
    }

    function storeCallCard(Cache memory cache, Card callCard) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(CALL_CARD_POS, Card.unwrap(callCard));
    }

    function storePlayerTurnIndex(Cache memory cache, uint8 idx) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(PLAYER_TURN_INDEX_POS, idx);
    }

    function storeStatus(Cache memory cache, GameStatus status) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(STATUS_POS, uint8(status));
    }

    function storeLastMoveTimestamp(Cache memory cache, uint40 timestamp) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU40(LAST_MOVE_TIMESTAMP_POS, timestamp);
    }

    function storePlayersLeftToJoin(Cache memory cache, uint8 playersLeft) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeNibble(PLAYERS_LEFT_TO_JOIN_POS, playersLeft);
    }

    function storeMaxPlayers(Cache memory cache, uint8 maxPlayers) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeNibble(MAX_PLAYERS_POS, maxPlayers);
    }

    function storeNumProposedPlayers(Cache memory cache, uint8 numProposedPlayers) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(NUM_PROPOSED_PLAYERS_POS, numProposedPlayers);
    }

    function storeHandSize(Cache memory cache, uint8 handSize) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(INITIAL_HAND_SIZE_POS, handSize);
    }

    function storePlayerStoreMap(Cache memory cache, PlayerStoreMap playerStoreMap) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(PLAYER_STORE_MAP_POS, PlayerStoreMap.unwrap(playerStoreMap));
    }

    function storeRuleset(Cache memory cache, IRuleset ruleset) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeAddress(RULESET_POS, address(ruleset));
    }

    function storeMarketDeckMap(Cache memory cache, DeckMap deckMap) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU64(MARKET_DECK_MAP_POS, DeckMap.unwrap(deckMap));
    }

    function storeHookPermissions(Cache memory cache, HookPermissions permissions) internal pure {
        CacheValue value = cache.value;
        cache.value = value.storeU8(HOOK_PERMISSIONS_POS, HookPermissions.unwrap(permissions));
    }

    function toStorage(Cache memory cache) internal {
        cache.value.toStorage(cache.slot);
    }
}
