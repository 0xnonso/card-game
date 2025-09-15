// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRuleset} from "./interfaces/IRuleset.sol";
import {Action, PendingAction, GameStatus} from "./libraries/CardEngineLib.sol";
import {DeckMap, PlayerStoreMap} from "./types/Map.sol";
import {Card} from "./types/Card.sol";
import {euint256} from "fhevm/lib/FHE.sol";
import {EInputData} from "./base/EInputHandler.sol";

interface ICardEngine {
    function createGame(
        EInputData calldata inputData,
        bytes calldata inputProof,
        address[] calldata proposedPlayers,
        IRuleset gameRuleSet,
        uint256 cardBitSize,
        uint256 cardDeckSize,
        uint8 maxPlayers,
        uint8 initialHandSize,
        bool enableManager
    ) external returns (uint256 gameId);

    function joinGame(uint256 gameId) external;
    function startGame(uint256 gameId) external;
    function commitMove(uint256 gameId, Action action, uint256 cardIndex, bytes memory extraData) external;
    function executeMove(uint256 gameId, Action action) external;
    function forfeit(uint256 gameId) external;
    function bootOut(uint256 gameId) external;

    function handleCommitMove(uint256 requestId, uint8 rawCard, bytes[] memory signatures) external;
    function handleCommitMarketDeck(uint256 requestId, uint256[2] memory marketDeck, bytes[] memory signatures)
        external;

    function getPlayerHand(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (DeckMap deckMap, euint256[2] memory hand);
    function getPlayerData(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (address playerAddr, DeckMap deckMap, PendingAction pendingAction, uint16 score);
    function getGameData(uint256 gameId)
        external
        view
        returns (
            address gameCreator,
            Card callCard,
            uint8 playerTurnIdx,
            GameStatus status,
            uint40 lastMoveTimestamp,
            PlayerStoreMap playerStoreMap,
            IRuleset ruleSet,
            DeckMap marketDeckMap
        );
}
