// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseModifier} from "../base/BaseModifier.sol";
import {ICardEngine} from "../interfaces/ICardEngine.sol";

import {IManagerHook, IManagerView} from "../interfaces/IManager.sol";
import {Action, Card, PlayerScoreData} from "../libraries/CardEngineLib.sol";

abstract contract BaseManager is BaseModifier, IManagerHook, IManagerView {
    error HookNotSupported();

    constructor(ICardEngine _cardEngine) BaseModifier(_cardEngine) {}

    function hasSpecialMoves(uint256, /*gameId*/ address, /*player*/ Card, /*playingCard*/ Action /*action*/ )
        external
        view
        virtual
        returns (bool)
    {
        revert HookNotSupported();
    }

    function canBootOut(uint256, /*gameId*/ address, /*player*/ uint40 /*playerLastMoveTimestamp*/ )
        external
        view
        virtual
        returns (bool)
    {
        revert HookNotSupported();
    }

    function onStartGame(uint256 /*gameId*/ ) external virtual onlyCardEngine returns (bool) {
        revert HookNotSupported();
    }

    function onJoinGame(uint256, /*gameId*/ address /*player*/ ) external virtual onlyCardEngine {
        revert HookNotSupported();
    }

    function onExecuteMove(uint256, /*gameId*/ address, /*player*/ Card, /*playingCard*/ Action /*action*/ )
        external
        virtual
        onlyCardEngine
        returns (bool)
    {
        revert HookNotSupported();
    }

    function onPlayerExit(uint256, /*gameId*/ address, /*player*/ bool /*forfeited*/ )
        external
        virtual
        onlyCardEngine
        returns (bool)
    {
        revert HookNotSupported();
    }

    function onFinishGame(
        uint256, /*gameId*/
        PlayerScoreData[] calldata, /*playersData*/
        uint256[2] calldata /*marketDeck*/
    ) external virtual onlyCardEngine {
        revert HookNotSupported();
    }
}
