// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IManagerHook, IManagerView} from "../interfaces/IManager.sol";
import {Action, PlayerScoreData} from "../libraries/CardEngineLib.sol";
import {Card} from "../types/Card.sol";
import {DeckMap} from "../types/Map.sol";

type HookPermissions is uint8;

using Hook for HookPermissions global;

library Hook {
    uint8 constant ON_START_GAME_FLAG = 1 << 0;
    uint8 constant ON_JOIN_GAME_FLAG = 1 << 1;
    uint8 constant ON_EXECUTE_MOVE_FLAG = 1 << 2;
    uint8 constant ON_FINISH_GAME_FLAG = 1 << 3;
    uint8 constant ON_PLAYER_EXIT_FLAG = 1 << 4;
    uint8 constant HAS_SPECIAL_MOVES_FLAG = 1 << 5;
    uint8 constant CAN_BOOT_OUT_FLAG = 1 << 6;

    function hasPermission(HookPermissions permissions, uint8 flag) internal pure returns (bool) {
        return (HookPermissions.unwrap(permissions) & flag) != 0;
    }

    function onStartGame(IManagerHook hook, HookPermissions permissions, uint256 gameId)
        internal
        returns (bool endGame)
    {
        if (permissions.hasPermission(ON_START_GAME_FLAG)) {
            endGame = hook.onStartGame(gameId);
        }
    }

    function onJoinGame(IManagerHook hook, HookPermissions permissions, uint256 gameId, address player) internal {
        if (permissions.hasPermission(ON_JOIN_GAME_FLAG)) {
            hook.onJoinGame(gameId, player);
        }
    }

    function onExecuteMove(
        IManagerHook hook,
        HookPermissions permissions,
        uint256 gameId,
        address player,
        Card playingCard,
        Action action
    ) internal returns (bool endGame) {
        if (permissions.hasPermission(ON_EXECUTE_MOVE_FLAG)) {
            endGame = hook.onExecuteMove(gameId, player, playingCard, action);
        }
    }

    function onFinishGame(
        IManagerHook hook,
        HookPermissions permissions,
        uint256 gameId,
        PlayerScoreData[] memory playersData,
        uint256[2] memory marketDeck
    ) internal {
        if (permissions.hasPermission(ON_FINISH_GAME_FLAG)) {
            hook.onFinishGame(gameId, playersData, marketDeck);
        }
    }

    function onPlayerExit(
        IManagerHook hook,
        HookPermissions permissions,
        uint256 gameId,
        address player,
        bool forfeited
    ) internal returns (bool endGame) {
        if (permissions.hasPermission(ON_PLAYER_EXIT_FLAG)) {
            endGame = hook.onPlayerExit(gameId, player, forfeited);
        }
    }

    function hasSpecialMoves(
        IManagerView hook,
        HookPermissions permissions,
        uint256 gameId,
        address player,
        Card playingCard,
        Action action
    ) internal view returns (bool isSpecial) {
        if (permissions.hasPermission(HAS_SPECIAL_MOVES_FLAG)) {
            isSpecial = hook.hasSpecialMoves(gameId, player, playingCard, action);
        }
    }

    function canBootOut(
        IManagerView hook,
        HookPermissions permissions,
        uint256 gameId,
        address player,
        uint40 playerLastMoveTimestamp,
        bool defaultResult
    ) internal view returns (bool) {
        if (permissions.hasPermission(CAN_BOOT_OUT_FLAG)) {
            return hook.canBootOut(gameId, player, playerLastMoveTimestamp);
        }
        return defaultResult;
    }
}
