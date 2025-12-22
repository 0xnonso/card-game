// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../helpers/Constants.sol";

import {IRuleset} from "../interfaces/IRuleset.sol";
import {GameData, GameStatus} from "../libraries/CardEngineLib.sol";
import {Card} from "./Card.sol";
import {HookPermissions} from "./Hook.sol";
import {DeckMap, PlayerStoreMap} from "./Map.sol";

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
    function loadAddress(CacheValue value, uint8 ptr) internal pure returns (address addr) {
        uint256 mask = Constants.ADDRESS_MASK;
        assembly {
            addr := and(shr(ptr, value), mask)
        }
    }

    function loadNibble(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr) & 0xf;
    }

    function loadU8(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr);
    }

    function loadU16(CacheValue value, uint8 ptr) internal pure returns (uint16) {
        return uint16(CacheValue.unwrap(value) >> ptr);
    }

    function loadU40(CacheValue value, uint8 ptr) internal pure returns (uint40) {
        return uint40(CacheValue.unwrap(value) >> ptr);
    }

    function loadU64(CacheValue value, uint8 ptr) internal pure returns (uint64) {
        return uint64(CacheValue.unwrap(value) >> ptr);
    }

    function loadU256(CacheValue value, uint8 ptr) internal pure returns (uint256) {
        return uint256(CacheValue.unwrap(value) >> ptr);
    }
}

library GameDataPositions {
    uint8 internal constant GAME_CREATOR = 0;
    uint8 internal constant CALL_CARD = 160;
    uint8 internal constant PLAYER_TURN_INDEX = 168;
    uint8 internal constant STATUS = 176;
    uint8 internal constant LAST_MOVE_TIMESTAMP = 184;
    uint8 internal constant NUM_PROPOSED_PLAYERS = 224;
    uint8 internal constant HOOK_PERMISSIONS = 232;
    uint8 internal constant PLAYER_STORE_MAP = 240;

    uint8 internal constant RULESET = 0;
    uint8 internal constant MARKET_DECK_MAP = 160;
    uint8 internal constant INITIAL_HAND_SIZE = 224;
    uint8 internal constant PLAYERS_LEFT_TO_JOIN = 232;
}

library PlayerDataPositions {
    uint8 internal constant PLAYER_ADDRESS = 0;
    uint8 internal constant DECKMAP = 160;
    uint8 internal constant PENDING_ACTION = 224;
    uint8 internal constant SCORE = 232;
    uint8 internal constant FORFEITED = 248;
}
