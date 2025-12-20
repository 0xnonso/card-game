// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../base/BaseManager.sol";
import {ICardEngine} from "../interfaces/ICardEngine.sol";

contract MockManager is BaseManager {
    bool public allowBootOut;
    bool public endGameAfter;

    bool public onStartGameFlip;
    bool public onExecuteMoveFlip;
    bool public onJoinGameFlip;
    bool public onPlayerExitFlip;
    bool public onFinishGameFlip;
    bool public allowSpecialMove;

    constructor(ICardEngine engine) BaseManager(engine) {}

    function setBootOutPermission(bool allowed) external {
        allowBootOut = allowed;
    }

    function enableSpecialMoves() external {
        allowSpecialMove = true;
    }

    function enableOnStartGame() external {
        onStartGameFlip = true;
    }

    function modifyGameStatus(bool _endGame) external {
        endGameAfter = _endGame;
    }

    function onStartGame(uint256) external override returns (bool) {
        return onStartGameFlip;
    }

    function onExecuteMove(uint256, address, Card, Action) external override returns (bool) {
        onExecuteMoveFlip = true;
        return endGameAfter;
    }

    function onJoinGame(uint256, address) external override onlyCardEngine {
        onJoinGameFlip = true;
    }

    function onPlayerExit(uint256, address, bool) external override onlyCardEngine returns (bool) {
        onPlayerExitFlip = true;
        return endGameAfter;
    }

    function onFinishGame(uint256, PlayerScoreData[] calldata, uint256[2] calldata) external override onlyCardEngine {
        onFinishGameFlip = true;
    }

    // IManagerView
    function hasSpecialMoves(uint256, address, Card, Action) external view override returns (bool) {
        return allowSpecialMove;
    }

    function canBootOut(uint256, address, uint40) external view override returns (bool) {
        return allowBootOut;
    }

    function createGame(ICardEngine.CreateGameParams calldata params) external returns (uint256 gameId) {
        gameId = CARD_ENGINE.createGame(params);
    }
}
