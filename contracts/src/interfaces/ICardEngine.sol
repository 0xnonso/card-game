// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {EInputData} from "../base/EInputHandler.sol";
import {Action, GameStatus, PlayerData} from "../libraries/CardEngineLib.sol";
import {Card} from "../types/Card.sol";

import {HookPermissions} from "../types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";
import {IRuleset} from "./IRuleset.sol";
import {euint256} from "@fhevm/solidity/lib/FHE.sol";

interface ICardEngine {
    struct CreateGameParams {
        EInputData input0;
        EInputData input1;
        bytes inputProof;
        address[] proposedPlayers;
        IRuleset gameRuleset;
        uint256 cardBitSize;
        uint256 cardDeckSize;
        uint8 maxPlayers;
        uint8 initialHandSize;
        HookPermissions hookPermissions;
    }

    function createGame(CreateGameParams calldata params) external returns (uint256 gameId);
    function joinGame(uint256 gameId) external;
    function startGame(uint256 gameId) external;
    function commitMove(uint256 gameId, Action action, uint256 cardIndex) external;
    function executeMove(uint256 gameId, Action action, bytes memory extraData) external;
    function forfeit(uint256 gameId) external;
    function bootOut(uint256 gameId, uint256 playerIndex) external;

    function getPlayerHand(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (DeckMap deckMap, euint256[2] memory hand);
    function getPlayerData(uint256 gameId, uint256 playerIndex) external view returns (PlayerData memory player);
    function getGameData(uint256 gameId)
        external
        view
        returns (
            address gameCreator,
            Card callCard,
            uint8 playerTurnIdx,
            GameStatus status,
            uint40 lastMoveTimestamp,
            uint8 playersLeftToJoin,
            HookPermissions hookPermissions,
            PlayerStoreMap playerStoreMap,
            IRuleset ruleset,
            DeckMap marketDeckMap,
            uint8 initialHandSize
        );
}
