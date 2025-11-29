// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseModifier} from "../base/BaseModifier.sol";

import {ICardEngine} from "../interfaces/ICardEngine.sol";
import {IRNG} from "../interfaces/IRNG.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action as GameAction} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {WhotCardStandardLibx8 as WhotCard} from "../libraries/WhotCardDeck.sol";

import {Card} from "../types/Card.sol";
import {PlayerStoreMap} from "../types/Map.sol";

// import "hardhat/console.sol";

contract WhotRuleset is BaseModifier, IRuleset {
    using ConditionalsLib for *;
    using WhotCard for Card;

    IRNG internal rng;

    constructor(address _rng, ICardEngine _cardEngine) BaseModifier(_cardEngine) {
        rng = IRNG(_rng);
    }

    function resolveMove(ResolveMoveParams memory params) public view onlyCardEngine returns (Effect memory effect) {
        Action[] memory actionsToExec = new Action[](1);
        effect.callCard = params.card;
        uint8 nextTurn = params.playerStoreMap.getNextIndex(params.currentPlayerIndex);
        effect.nextPlayerIndex = nextTurn;
        if (params.gameAction.eqs(GameAction.Play)) {
            if (!params.callCard.matchWhot(params.card)) {
                revert("WhotRuleset: Cards don't match");
            }

            if (params.card.isPickTwo()) {
                if (params.card.isPickFour() && params.isSpecial) {
                    actionsToExec[0].op = EngineOp.PickPendingFour;
                } else {
                    actionsToExec[0].op = EngineOp.PickPendingTwo;
                }
                actionsToExec[0].againstPlayerIndex = nextTurn;
            } else if (params.card.isPickThree() && params.isSpecial) {
                actionsToExec[0].op = EngineOp.PickPendingThree;
                actionsToExec[0].againstPlayerIndex = nextTurn;
            } else if (params.card.isHoldOn()) {
                effect.nextPlayerIndex = params.playerStoreMap.getNextIndex(effect.nextPlayerIndex);
            } else if (params.card.isSuspension()) {
                effect.nextPlayerIndex = params.currentPlayerIndex; // Set turn to 0 for suspension op
            } else if (params.card.isGeneralMarket()) {
                actionsToExec[0].op = EngineOp.PickOne;
                actionsToExec[0].againstPlayerIndex = type(uint8).max; // Set turn to 0 for general market op
                effect.nextPlayerIndex = params.currentPlayerIndex;
            } else if (params.card.isWishCard()) {
                (WhotCard.CardShape wishShape) = abi.decode(params.extraData, (WhotCard.CardShape));
                effect.callCard = WhotCard.makeWhotWish(wishShape);
                effect.nextPlayerIndex = params.currentPlayerIndex;
            }
        } else if (params.gameAction.eqs(GameAction.Defend)) {
            if (!params.isSpecial) {
                revert("Defense not enabled");
            }
            if (params.pendingAction == 4) {
                actionsToExec[0].op = EngineOp.PickTwo;
                actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
            }
            effect.nextPlayerIndex = nextTurn;
        } else if (params.gameAction.eqs(GameAction.Draw)) {
            if (params.pendingAction > 0) {
                actionsToExec[0].op = EngineOp(params.pendingAction % 8);
            } else {
                actionsToExec[0].op = EngineOp.PickOne;
            }
            actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
        } else {
            revert("Invalid action");
        }
        effect.actions = actionsToExec;
    }

    function afterResolveMove(ResolveMoveParams memory params) public onlyCardEngine {}

    function computeStartIndex(PlayerStoreMap playerStoreMap) public view returns (uint8 startIdx) {
        // return uint8(rng.generatePseudoRandomNumber() % playerStoreMap.len());
    }

    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        public
        pure
        returns (uint8 nextTurnIdx)
    {
        return playerStoreMap.getNextIndex(uint8(currentPlayerIndex));
    }

    function isSpecialMoveCard(Card card) public pure returns (bool) {
        return false;
    }

    function getCardAttributes(Card card, uint256)
        /**
         * cardSize
         */
        public
        pure
        returns (uint256 cardId, uint256 cardValue)
    {
        return (uint256(card.shape()), card.number());
    }

    function supportsCardSize(uint256 cardBitsSize) public pure returns (bool) {
        return cardBitsSize == WhotCard.cardSize();
    }
}
