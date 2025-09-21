// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Action as GameAction, PendingAction as GamePendingAction} from "../libraries/CardEngineLib.sol";
import {Card} from "../types/Card.sol";
import {PlayerStoreMap} from "../types/Map.sol";

interface IRuleset {
    enum EngineOp {
        None,
        PickOne,
        PickTwo,
        PickThree,
        PickFour,
        PickFive,
        PickSix,
        PickSeven,
        PickEight,
        PickPendingOne,
        PickPendingTwo,
        PickPendingThree,
        PickPendingFour,
        PickPendingFive,
        PickPendingSix,
        PickPendingSeven,
        PickPendingEight
    }

    struct Effect {
        EngineOp op;
        Card callCard;
        uint8 againstPlayerIndex;
        uint8 nextPlayerIndex;
    }

    struct ResolveMoveParams {
        GameAction gameAction;
        GamePendingAction pendingAction;
        Card card;
        Card callCard;
        uint256 cardSize;
        uint8 currentPlayerIndex;
        PlayerStoreMap playerStoreMap;
        bool isSpecial;
        bytes extraData;
    }

    function resolveMove(ResolveMoveParams memory params) external view returns (Effect memory);
    function computeStartIndex(PlayerStoreMap playerStoreMap) external view returns (uint8 startIndex);
    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        external
        view
        returns (uint8 nextPlayerIndex);
    function isSpecialMoveCard(Card card) external view returns (bool);
    function getCardAttributes(Card card, uint256 cardSize) external view returns (uint256 shape, uint256 cardNumber);
    function supportsCardSize(uint256 cardSize) external view returns (bool);
}
