// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Action} from "../libraries/CardEngineLib.sol";
import {Card} from "../types/Card.sol";

interface IManagerView {
    function hasSpecialMoves(uint256 gameId, address player, Card playingCard, Action action)
        external
        view
        returns (bool);

    function canBootOut(uint256 gameId, address player, uint40 playerLastMoveTimestamp) external view returns (bool);
}

interface IManagerHook {
    function onStartGame(uint256 gameId) external returns (bool);
    function onJoinGame(uint256 gameId, address player) external;
    function onExecuteMove(uint256 gameId, address player, Card playingCard, Action action) external;
    function onFinishGame(uint256 gameId, uint256[] calldata playersScoreData) external;
}
