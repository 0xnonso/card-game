// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GameData, GameStatus} from "../libraries/CardEngineLib.sol";

import {Card} from "./Card.sol";
import {PlayerStoreMap} from "./Map.sol";

type CacheValue is uint256;

using CacheManager for CacheValue global;

library CacheManager {
    function toCachedValue(uint256 slot) internal view returns (CacheValue value) {
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }

    function toStorage(CacheValue value, uint256 slot) internal {
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }

    function storeAddress(CacheValue value, uint8 ptr, address addr) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffffffffffffffffffffffffffffffffffffffff))), shl(ptr, addr))
        }
    }

    function readAddress(CacheValue value, uint8 ptr) internal pure returns (address) {
        return address(uint160(CacheValue.unwrap(value) >> ptr));
    }

    function storeNibble(CacheValue value, uint8 ptr, uint8 nibble) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0x0f))), shl(ptr, and(nibble, 0x0f)))
        }
    }

    function readNibble(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr) & 0x0f;
    }

    function storeUint8(CacheValue value, uint8 ptr, uint8 _uint8) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xff))), shl(ptr, _uint8))
        }
    }

    function readUint8(CacheValue value, uint8 ptr) internal pure returns (uint8) {
        return uint8(CacheValue.unwrap(value) >> ptr);
    }

    function storeUint16(CacheValue value, uint8 ptr, uint16 _uint16) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffff))), shl(ptr, _uint16))
        }
    }

    function readUint16(CacheValue value, uint8 ptr) internal pure returns (uint16) {
        return uint16(CacheValue.unwrap(value) >> ptr);
    }

    function storeUint40(CacheValue value, uint8 ptr, uint40 _uint40) internal pure returns (CacheValue newValue) {
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffffffffff))), shl(ptr, _uint40))
        }
    }

    function readUint40(CacheValue value, uint8 ptr) internal pure returns (uint40) {
        return uint40(CacheValue.unwrap(value) >> ptr);
    }

    function storeUint256(CacheValue value, uint8 ptr, uint256 _uint256) internal pure returns (CacheValue newValue) {
        // forgefmt: disable-next-item
        assembly ("memory-safe") {
            newValue := or(and(value, not(shl(ptr, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff))), shl(ptr, _uint256))
        }
    }

    function readUint256(CacheValue value, uint8 ptr) internal pure returns (uint256) {
        return uint256(CacheValue.unwrap(value) >> ptr);
    }
}

library GameCacheManager {
    function toCachedValue(GameData storage $) internal view returns (CacheValue value, uint256 slot) {
        assembly ("memory-safe") {
            slot := $.slot
        }
        value = CacheManager.toCachedValue(slot);
    }

    function gameCreator(CacheValue value) internal pure returns (address) {
        return value.readAddress(0);
    }

    function callCard(CacheValue value) internal pure returns (Card) {
        return Card.wrap(value.readUint8(160));
    }

    function playerTurnIndex(CacheValue value) internal pure returns (uint8) {
        return value.readUint8(168);
    }

    function status(CacheValue value) internal pure returns (GameStatus) {
        return GameStatus(value.readUint8(176));
    }

    function lastMoveTimestamp(CacheValue value) internal pure returns (uint40) {
        return value.readUint40(184);
    }

    function playersLeftToJoin(CacheValue value) internal pure returns (uint8) {
        return value.readNibble(224);
    }

    function maxPlayers(CacheValue value) internal pure returns (uint8) {
        return value.readNibble(228);
    }

    function initialHandSize(CacheValue value) internal pure returns (uint8) {
        return value.readUint8(232);
    }

    function playerStoreMap(CacheValue value) internal pure returns (PlayerStoreMap) {
        return PlayerStoreMap.wrap(value.readUint16(240));
    }

    function updateGameCreator(CacheValue value, address _gameCreator) internal pure returns (CacheValue newValue) {
        newValue = value.storeAddress(0, _gameCreator);
    }

    function updateCallCard(CacheValue value, Card _callCard) internal pure returns (CacheValue newValue) {
        newValue = value.storeUint8(160, Card.unwrap(_callCard));
    }

    function updatePlayerTurnIndex(CacheValue value, uint8 _playerTurnIndex)
        internal
        pure
        returns (CacheValue newValue)
    {
        newValue = value.storeUint8(168, _playerTurnIndex);
    }

    function updateStatus(CacheValue value, GameStatus _status) internal pure returns (CacheValue newValue) {
        newValue = value.storeUint8(176, uint8(_status));
    }

    function updateLastMoveTimestamp(CacheValue value, uint40 _lastMoveTimestamp)
        internal
        pure
        returns (CacheValue newValue)
    {
        newValue = value.storeUint40(184, _lastMoveTimestamp);
    }

    function updatePlayersLeftToJoin(CacheValue value, uint8 _playersLeftToJoin)
        internal
        pure
        returns (CacheValue newValue)
    {
        newValue = value.storeNibble(224, _playersLeftToJoin);
    }

    function updateMaxPlayers(CacheValue value, uint8 _maxPlayers) internal pure returns (CacheValue newValue) {
        newValue = value.storeNibble(228, _maxPlayers);
    }

    function updateHandSize(CacheValue value, uint8 _handSize) internal pure returns (CacheValue newValue) {
        newValue = value.storeUint8(232, _handSize);
    }

    function updatePlayerStoreMap(CacheValue value, PlayerStoreMap _playerStoreMap)
        internal
        pure
        returns (CacheValue newValue)
    {
        newValue = value.storeUint16(240, PlayerStoreMap.unwrap(_playerStoreMap));
    }
}

// using TournamentCacheManager for TournamentCacheValue global;

// library TournamentCacheManager {}
