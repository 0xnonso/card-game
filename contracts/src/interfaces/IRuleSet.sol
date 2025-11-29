// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Action as GameAction} from "../libraries/CardEngineLib.sol";
import {Card} from "../types/Card.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";
import {euint256} from "@fhevm/solidity/lib/FHE.sol";

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

    struct Action {
        EngineOp op;
        uint8 againstPlayerIndex;
    }

    struct Effect {
        Action[] actions;
        Card callCard;
        uint8 nextPlayerIndex;
        bool togglePSMDirection;
        bool currentPlayerExit;
        bool invokeAfterResolveMove;
    }

    struct ResolveMoveParams {
        GameAction gameAction;
        uint8 pendingAction;
        Card card;
        Card callCard;
        uint256 cardSize;
        uint8 currentPlayerIndex;
        DeckMap playerDeckMap;
        euint256[2] playerHand;
        PlayerStoreMap playerStoreMap;
        bool isSpecial;
        bytes extraData;
    }

    function resolveMove(ResolveMoveParams calldata params) external returns (Effect memory);
    function afterResolveMove(ResolveMoveParams calldata params) external;
    function computeStartIndex(PlayerStoreMap playerStoreMap) external view returns (uint8 startIndex);
    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        external
        view
        returns (uint8 nextPlayerIndex);
    function isSpecialMoveCard(Card card) external view returns (bool);
    function getCardAttributes(Card card, uint256 cardSize) external view returns (uint256 shape, uint256 cardNumber);
    function supportsCardSize(uint256 cardSize) external view returns (bool);
}
