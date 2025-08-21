// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Action} from "../libraries/WhotLib.sol";
import {WhotCard} from "../types/WhotCard.sol";

interface IWhotManagerView {
    function hasSpecialMoves(uint256 gameId, address player, WhotCard playingCard, Action action)
        external
        view
        returns (bool);

    function canBootOut(uint256 gameId, address player, uint40 playerLastMoveTimestamp)
        external
        view
        returns (bool);
}

interface IWhotManagerHook {
    function onJoinGame(uint256 gameId, address player) external;

    function onExecuteMove(uint256 gameId, address player, WhotCard playingCard, Action action)
        external;

    function onFinishGame(uint256 gameId, uint256[] calldata playersScoreData) external;

    function onStartGame(uint256 gameId) external returns (bool);
}
