// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action, CardEngineLib, GameData, GameStatus, PendingAction, PlayerData} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {CacheManager, CacheValue} from "../types/Cache.sol";
import {Card, CardLib} from "../types/Card.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";

contract CachePositionBase {
    uint8 constant GAME_CREATOR_POS = 0;
    uint8 constant CALL_CARD_POS = 160;
    uint8 constant PLAYER_TURN_INDEX_POS = 168;
    uint8 constant STATUS_POS = 176;
    uint8 constant LAST_MOVE_TIMESTAMP_POS = 184;
    uint8 constant PLAYERS_LEFT_TO_JOIN_POS = 224;
    uint8 constant MAX_PLAYERS_POS = 228;
    uint8 constant NUM_PROPOSED_PLAYERS_POS = 232;
    uint8 constant INITIAL_HAND_SIZE_POS = 240;
    uint8 constant PLAYER_STORE_MAP_POS = 248;

    uint8 constant RULESET_POS = 0;
    uint8 constant MARKET_DECK_MAP_POS = 160;

    /// READ

    function loadCache(GameData storage game, uint256 indexFrom)
        internal
        view
        returns (CacheValue value, uint256 slot)
    {
        assembly ("memory-safe") {
            slot := add(game.slot, indexFrom)
        }
        value = CacheManager.toCachedValue(slot);
    }

    function loadGameCreator(CacheValue value) internal pure returns (address) {
        return value.loadAddress(GAME_CREATOR_POS);
    }

    function loadCallCard(CacheValue value) internal pure returns (Card) {
        return Card.wrap(value.loadU8(CALL_CARD_POS));
    }

    function loadPlayerTurnIndex(CacheValue value) internal pure returns (uint8) {
        return value.loadU8(PLAYER_TURN_INDEX_POS);
    }

    function loadStatus(CacheValue value) internal pure returns (GameStatus) {
        return GameStatus(value.loadU8(STATUS_POS));
    }

    function loadLastMoveTimestamp(CacheValue value) internal pure returns (uint40) {
        return value.loadU40(LAST_MOVE_TIMESTAMP_POS);
    }

    function loadPlayersLeftToJoin(CacheValue value) internal pure returns (uint8) {
        return value.loadNibble(PLAYERS_LEFT_TO_JOIN_POS);
    }

    function loadMaxPlayers(CacheValue value) internal pure returns (uint8) {
        return value.loadNibble(MAX_PLAYERS_POS);
    }

    function loadNumProposedPlayers(CacheValue value) internal pure returns (uint8) {
        return value.loadU8(NUM_PROPOSED_PLAYERS_POS);
    }

    function loadHandSize(CacheValue value) internal pure returns (uint8) {
        return value.loadU8(INITIAL_HAND_SIZE_POS);
    }

    function loadPlayerStoreMap(CacheValue value) internal pure returns (PlayerStoreMap) {
        return PlayerStoreMap.wrap(value.loadU8(PLAYER_STORE_MAP_POS));
    }

    function loadRuleset(CacheValue value) internal pure returns (IRuleset) {
        return IRuleset(value.loadAddress(RULESET_POS));
    }

    function loadMarketDeckMap(CacheValue value) internal pure returns (DeckMap) {
        return DeckMap.wrap(value.loadU64(MARKET_DECK_MAP_POS));
    }

    /// WRITE

    function storeGameCreator(CacheValue value, address gameCreator) internal pure returns (CacheValue) {
        return value.storeAddress(GAME_CREATOR_POS, gameCreator);
    }

    function storeCallCard(CacheValue value, Card callCard) internal pure returns (CacheValue) {
        return value.storeU8(CALL_CARD_POS, Card.unwrap(callCard));
    }

    function storePlayerTurnIndex(CacheValue value, uint8 idx) internal pure returns (CacheValue) {
        return value.storeU8(PLAYER_TURN_INDEX_POS, idx);
    }

    function storeStatus(CacheValue value, GameStatus status) internal pure returns (CacheValue) {
        return value.storeU8(STATUS_POS, uint8(status));
    }

    function storeLastMoveTimestamp(CacheValue value, uint40 timestamp) internal pure returns (CacheValue) {
        return value.storeU40(LAST_MOVE_TIMESTAMP_POS, timestamp);
    }

    function storePlayersLeftToJoin(CacheValue value, uint8 playersLeft) internal pure returns (CacheValue) {
        return value.storeNibble(PLAYERS_LEFT_TO_JOIN_POS, playersLeft);
    }

    function storeMaxPlayers(CacheValue value, uint8 maxPlayers) internal pure returns (CacheValue) {
        return value.storeNibble(MAX_PLAYERS_POS, maxPlayers);
    }

    function storeNumProposedPlayers(CacheValue value, uint8 numProposedPlayers) internal pure returns (CacheValue) {
        return value.storeU8(NUM_PROPOSED_PLAYERS_POS, numProposedPlayers);
    }

    function storeHandSize(CacheValue value, uint8 handSize) internal pure returns (CacheValue) {
        return value.storeU8(INITIAL_HAND_SIZE_POS, handSize);
    }

    function storePlayerStoreMap(CacheValue value, PlayerStoreMap playerStoreMap) internal pure returns (CacheValue) {
        return value.storeU8(PLAYER_STORE_MAP_POS, PlayerStoreMap.unwrap(playerStoreMap));
    }

    function storeRuleset(CacheValue value, IRuleset ruleset) internal pure returns (CacheValue) {
        return value.storeAddress(RULESET_POS, address(ruleset));
    }

    function storeMarketDeckMap(CacheValue value, DeckMap deckMap) internal pure returns (CacheValue) {
        return value.storeU64(MARKET_DECK_MAP_POS, DeckMap.unwrap(deckMap));
    }
}
