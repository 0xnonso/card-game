// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GameData, GameStatus} from "../libraries/WhotLib.sol";
import {PlayerStoreMap} from "./Map.sol";
import {WhotCard} from "./WhotCard.sol";

type GameCacheValue is uint256;

using GameCacheManager for GameCacheValue global;

library GameCacheManager {
    uint256 constant GAME_CREATOR_MASK =
        0xffffffffffffffffffffffff0000000000000000000000000000000000000000;
    uint256 constant CALL_CARD_MASK =
        0xffffffffffffffffffffff00ffffffffffffffffffffffffffffffffffffffff;
    uint256 constant PLAYER_TURN_MASK =
        0xffffffffffffffffffff00ffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant GAME_STATUS_MASK =
        0xffffffffffffffffff00ffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant LAST_MOVE_MASK =
        0xffffffff0000000000ffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant PLAYERS_LEFT_TO_JOIN_MASK =
        0xfffffff0ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant MAX_PLAYERS_MASK =
        0xffffff0fffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant HAND_SIZE_MASK =
        0xffff00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant PLAYER_STORE_MASK =
        0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function toCachedValue(GameData storage $)
        internal
        view
        returns (GameCacheValue value, uint256 slot)
    {
        assembly ("memory-safe") {
            slot := $.slot
            value := sload(slot)
        }
    }

    function gameCreator(GameCacheValue value) internal pure returns (address) {
        return address(uint160(GameCacheValue.unwrap(value)));
    }

    function callCard(GameCacheValue value) internal pure returns (WhotCard) {
        return WhotCard.wrap(uint8(GameCacheValue.unwrap(value) >> 160));
    }

    function playerTurnIndex(GameCacheValue value) internal pure returns (uint8) {
        return uint8(GameCacheValue.unwrap(value) >> 168);
    }

    function status(GameCacheValue value) internal pure returns (GameStatus) {
        return GameStatus(uint8(GameCacheValue.unwrap(value) >> 176));
    }

    function lastMoveTimestamp(GameCacheValue value) internal pure returns (uint40) {
        return uint40(GameCacheValue.unwrap(value) >> 184);
    }

    function playersLeftToJoin(GameCacheValue value) internal pure returns (uint8) {
        return uint8(GameCacheValue.unwrap(value) >> 224) & 0x0f;
    }

    function maxPlayers(GameCacheValue value) internal pure returns (uint8) {
        return uint8(GameCacheValue.unwrap(value) >> 228) & 0x0f;
    }

    function initialHandSize(GameCacheValue value) internal pure returns (uint256) {
        return uint8(GameCacheValue.unwrap(value) >> 232);
    }

    function playerStoreMap(GameCacheValue value) internal pure returns (PlayerStoreMap) {
        return PlayerStoreMap.wrap(uint16(GameCacheValue.unwrap(value) >> 240));
    }

    function updateGameCreator(GameCacheValue value, address _gameCreator)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, GAME_CREATOR_MASK), _gameCreator)
        }
    }

    function updateCallCard(GameCacheValue value, WhotCard _callCard)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, CALL_CARD_MASK), shl(160, _callCard))
        }
    }

    function updatePlayerTurnIndex(GameCacheValue value, uint8 _playerTurnIndex)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, PLAYER_TURN_MASK), shl(168, _playerTurnIndex))
        }
    }

    function updateStatus(GameCacheValue value, GameStatus _status)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, GAME_STATUS_MASK), shl(176, _status))
        }
    }

    function updateLastMoveTimestamp(GameCacheValue value, uint40 _lastMoveTimestamp)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, LAST_MOVE_MASK), shl(184, _lastMoveTimestamp))
        }
    }

    function updatePlayersLeftToJoin(GameCacheValue value, uint8 _playersLeftToJoin)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue :=
                or(and(value, PLAYERS_LEFT_TO_JOIN_MASK), shl(224, and(_playersLeftToJoin, 0x0f)))
        }
    }

    function updateMaxPlayers(GameCacheValue value, uint8 _maxPlayers)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, MAX_PLAYERS_MASK), shl(224, and(_maxPlayers, 0xf0)))
        }
    }

    function updateHandSize(GameCacheValue value, uint8 _handSize)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, HAND_SIZE_MASK), shl(232, _handSize))
        }
    }

    function updatePlayerStoreMap(GameCacheValue value, PlayerStoreMap _playerStoreMap)
        internal
        pure
        returns (GameCacheValue newValue)
    {
        assembly ("memory-safe") {
            newValue := or(and(value, PLAYER_STORE_MASK), shl(240, _playerStoreMap))
        }
    }

    // define function to load a certain number of slots to storage
    function toStorage(GameCacheValue value, uint256 slot) internal {
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }
}

type TournamentCacheValue is uint256;

using TournamentCacheManager for TournamentCacheValue global;

library TournamentCacheManager {}
