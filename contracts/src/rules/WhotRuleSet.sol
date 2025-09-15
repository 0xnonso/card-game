// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRNG} from "../interfaces/IRNG.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {Action as GameAction, PendingAction as GamePendingAction} from "../libraries/CardEngineLib.sol";
import {Card, WhotCardStandardLibx8} from "../types/Card.sol";
import {PlayerStoreMap} from "../types/Map.sol";

// This contract contains the rules for the Whot game.
// It includes functions to validate moves, check game state, etc.
contract WhotRuleset is IRuleset {
    using ConditionalsLib for *;
    using WhotCardStandardLibx8 for Card;

    uint256 constant CARD_SIZE_8 = 8;
    IRNG internal rng;

    constructor(address _rng) {
        rng = IRNG(_rng);
    }

    // Example function to validate a move
    function resolveMove(ResolveMoveParams memory params) public view override returns (Effect memory effect) {
        if (!params.callCard.matchWhot(params.card)) {
            revert();
        }

        effect.callCard = params.callCard;
        if (params.gameAction.eqs(GameAction.Play)) {
            if (params.card.pickTwo()) {
                if (params.card.pickFour() && params.isSpecial) {
                    effect.op = EngineOp.PickPendingFour;
                } else {
                    effect.op = EngineOp.PickPendingTwo;
                }
                uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                effect.againstPlayerIndex = nextTurn; // Set turn to 1 for pick actions
                effect.nextPlayerIndex = nextTurn;
            }

            if (params.card.pickThree() && params.isSpecial) {
                effect.op = EngineOp.PickPendingThree;
                uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                effect.againstPlayerIndex = nextTurn;
                effect.nextPlayerIndex = nextTurn;
            }

            if (params.card.holdOn()) {
                PlayerStoreMap playerStoreMap = params.playerStoreMap;
                effect.nextPlayerIndex =
                    playerStoreMap.getNextIndexFrom_RL(playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex)); // Set turn to 1 for hold on op
            }

            if (params.card.suspension()) {
                effect.nextPlayerIndex = params.currentPlayerIndex; // Set turn to 0 for suspension op
            }

            if (params.card.generalMarket()) {
                effect.op = EngineOp.PickOne;
                effect.againstPlayerIndex = type(uint8).max; // Set turn to 0 for general market op
                effect.nextPlayerIndex = params.currentPlayerIndex;
            }

            if (params.card.iWish()) {
                (WhotCardStandardLibx8.CardShape wishShape) =
                    abi.decode(params.extraData, (WhotCardStandardLibx8.CardShape));
                effect.callCard = WhotCardStandardLibx8.makeWhotWish(wishShape);
            }
        } else if (params.gameAction.eqs(GameAction.Defend)) {
            if (!params.isSpecial) {
                revert(); //revert DefenseNotEnabled();
            }
            uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
            if (params.pendingAction.eqs(GamePendingAction.PickFour)) {
                effect.op = EngineOp.PickTwo;
                effect.againstPlayerIndex = params.currentPlayerIndex;
            }
            effect.nextPlayerIndex = nextTurn;
        } else {
            revert("WhotRuleset: Invalid op");
        }
    }

    function computeStartIndex(PlayerStoreMap playerStoreMap) public view override returns (uint8 startIdx) {
        return uint8(rng.generatePseudoRandomNumber() % playerStoreMap.len());
    }

    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        public
        view
        override
        returns (uint8 nextTurnIdx)
    {
        return playerStoreMap.getNextIndexFrom_RL(uint8(currentPlayerIndex));
    }

    function isSpecialMoveCard(Card card) public view override returns (bool) {}

    function getCardAttributes(Card card, uint256)
        /**
         * cardSize
         */
        public
        view
        override
        returns (uint256 cardId, uint256 cardValue)
    {
        return (uint256(card.shape()), card.number());
    }

    function supportsCardSize(uint256 cardBitsSize) public pure override returns (bool) {
        return cardBitsSize == CARD_SIZE_8;
    }
}
