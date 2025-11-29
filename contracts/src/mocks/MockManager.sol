// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../base/BaseManager.sol";
import {ICardEngine} from "../interfaces/ICardEngine.sol";

contract MockManager is BaseManager {
    bool public allowBootOut;

    constructor(ICardEngine engine) BaseManager(engine) {}

    function setBootOutPermission(bool allowed) external {
        allowBootOut = allowed;
    }

    function onStartGame(uint256) external pure override returns (bool) {
        return false;
    }

    function onExecuteMove(uint256, address, Card, Action) external pure override returns (bool) {
        return false;
    }

    function onJoinGame(uint256, address) external override onlyCardEngine {}

    function onPlayerExit(uint256, address, bool) external override onlyCardEngine {}

    function onFinishGame(uint256, PlayerScoreData[] calldata, uint256[2] calldata)
        external
        override
        onlyCardEngine
    {}

    // IManagerView
    function hasSpecialMoves(uint256, address, Card, Action) external pure override returns (bool) {
        return false;
    }

    function canBootOut(uint256, address, uint40) external view override returns (bool) {
        return allowBootOut;
    }

    function createGame(ICardEngine.CreateGameParams calldata params) external returns (uint256 gameId) {
        gameId = cardEngine.createGame(params);
    }
}
