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

contract WhotRuleset is BaseModifier, IRuleset {
    using ConditionalsLib for *;
    using WhotCard for Card;

    IRNG internal rng;

    error PlayerCardDoesNotMatchCallCard();
    error InvalidAction();
    error DefenseNotEnabled();

    constructor(address _rng, ICardEngine _cardEngine) BaseModifier(_cardEngine) {
        rng = IRNG(_rng);
    }

    function resolveMove(ResolveMoveParams memory params) public view onlyCardEngine returns (Effect memory effect) {
        Action[] memory actionsToExec = new Action[](1);
        bool noActionFlag;
        uint8 nextTurn = params.playerStoreMap.getNextIndex(params.currentPlayerIndex);
        effect.nextPlayerIndex = nextTurn;
        effect.callCard = params.callCard;
        if (params.action.eqs(GameAction.Play)) {
            effect.callCard = params.card;
            if (!params.callCard.matchWhot(params.card)) {
                revert PlayerCardDoesNotMatchCallCard();
            }

            if (params.card.isPickTwo()) {
                if (params.card.isPickFour() && params.isSpecial) {
                    actionsToExec[0].op = EngineOp.DealPendingFour;
                } else {
                    actionsToExec[0].op = EngineOp.DealPendingTwo;
                }
                actionsToExec[0].againstPlayerIndex = nextTurn;
            } else if (params.card.isPickThree() && params.isSpecial) {
                actionsToExec[0].op = EngineOp.DealPendingThree;
                actionsToExec[0].againstPlayerIndex = nextTurn;
            } else if (params.card.isHoldOn()) {
                noActionFlag = true;
                effect.nextPlayerIndex = params.playerStoreMap.getNextIndex(effect.nextPlayerIndex);
            } else if (params.card.isSuspension()) {
                noActionFlag = true;
                effect.nextPlayerIndex = params.currentPlayerIndex; // Set turn to 0 for suspension op
            } else if (params.card.isGeneralMarket()) {
                actionsToExec[0].op = EngineOp.DealOne;
                actionsToExec[0].againstPlayerIndex = type(uint8).max; // Set turn to 0 for general market op
                effect.nextPlayerIndex = params.currentPlayerIndex;
            } else if (params.card.isWishCard()) {
                noActionFlag = true;
                (WhotCard.CardShape wishShape) = abi.decode(params.extraData, (WhotCard.CardShape));
                effect.callCard = WhotCard.makeWhotWish(wishShape);
                effect.nextPlayerIndex = params.currentPlayerIndex;
            }
        } else if (params.action.eqs(GameAction.Defend)) {
            if (!params.isSpecial) {
                revert DefenseNotEnabled();
            }

            if (params.pendingAction == 4) {
                actionsToExec[0].op = EngineOp.DealTwo;
                actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
            }
        } else if (params.action.eqs(GameAction.Draw)) {
            if (params.pendingAction > 0) {
                actionsToExec[0].op = EngineOp(params.pendingAction % 8);
            } else {
                actionsToExec[0].op = EngineOp.DealOne;
            }
            actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
        } else {
            revert InvalidAction();
        }
        if (noActionFlag) {
            actionsToExec = new Action[](0);
        }
        effect.actions = actionsToExec;
    }

    function afterResolveMove(ResolveMoveParams memory params) public onlyCardEngine {}

    function computeStartIndex(PlayerStoreMap playerStoreMap) public view returns (uint8 startIdx) {
        return uint8(rng.generatePseudoRandomNumber() % playerStoreMap.len());
    }

    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        public
        pure
        returns (uint8 nextTurnIdx)
    {
        return playerStoreMap.getNextIndex(uint8(currentPlayerIndex));
    }

    function isSpecialMoveCard(Card /*card*/ ) public pure returns (bool) {
        return false;
    }

    function getCardAttributes(Card card, uint256 /*cardSize*/ ) public pure returns (uint256, uint256) {
        return (uint256(card.shape()), card.number());
    }

    function supportsCardSize(uint256 cardBitsSize) public pure returns (bool) {
        return cardBitsSize == WhotCard.cardSize();
    }
}
