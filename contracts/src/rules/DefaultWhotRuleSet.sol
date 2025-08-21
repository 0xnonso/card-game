// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRNG} from "../interfaces/IRNG.sol";
import {IRuleSet} from "../interfaces/IRuleSet.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {Action as GameAction, PendingAction as GamePendingAction} from "../libraries/WhotLib.sol";
import {PlayerStoreMap} from "../types/Map.sol";
import {WhotCard, WhotCardStandardLibx8} from "../types/WhotCard.sol";

// This contract contains the rules for the Whot game.
// It includes functions to validate moves, check game state, etc.
contract DefaultWhotRuleSet is IRuleSet {
    using ConditionalsLib for *;
    using WhotCardStandardLibx8 for WhotCard;

    uint256 constant CARD_SIZE_8 = 8;
    IRNG internal rng;

    constructor(address _rng) {
        rng = IRNG(_rng);
    }

    // Example function to validate a move
    function validateMove(MoveValidationParams memory params)
        public
        view
        override
        returns (MoveValidationResult memory result)
    {
        if (!params.callCard.matchWhot(params.card)) {
            revert();
        }

        result.callCard = params.callCard;
        if (params.gameAction.eqs(GameAction.Play)) {
            if (params.card.pickTwo()) {
                if (params.card.pickFour() && params.isSpecial) {
                    result.action = Action.PickPendingFour;
                } else {
                    result.action = Action.PickPendingTwo;
                }
                uint8 nextTurn =
                    params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                result.againstPlayerIndex = nextTurn; // Set turn to 1 for pick actions
                result.nextPlayerIndex = nextTurn;
            }

            if (params.card.pickThree() && params.isSpecial) {
                result.action = Action.PickPendingThree;
                uint8 nextTurn =
                    params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                result.againstPlayerIndex = nextTurn;
                result.nextPlayerIndex = nextTurn;
            }

            if (params.card.holdOn()) {
                PlayerStoreMap playerStoreMap = params.playerStoreMap;
                result.nextPlayerIndex = playerStoreMap.getNextIndexFrom_RL(
                    playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex)
                ); // Set turn to 1 for hold on action
            }

            if (params.card.suspension()) {
                result.nextPlayerIndex = params.currentPlayerIndex; // Set turn to 0 for suspension action
            }

            if (params.card.generalMarket()) {
                result.action = Action.PickOne;
                result.againstPlayerIndex = type(uint8).max; // Set turn to 0 for general market action
                result.nextPlayerIndex = params.currentPlayerIndex;
            }

            if (params.card.iWish()) {
                (WhotCardStandardLibx8.CardShape wishShape) =
                    abi.decode(params.extraData, (WhotCardStandardLibx8.CardShape));
                result.callCard = WhotCardStandardLibx8.makeWhotWish(wishShape);
            }
        } else if (params.gameAction.eqs(GameAction.Defend)) {
            if (!params.isSpecial) {
                revert(); //revert DefenseNotEnabled();
            }
            uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
            if (params.pendingAction.eqs(GamePendingAction.PickFour)) {
                result.action = Action.PickTwo;
                result.againstPlayerIndex = params.currentPlayerIndex;
            }
            result.nextPlayerIndex = nextTurn;
        } else {
            revert("DefaultWhotRuleSet: Invalid action");
        }
    }

    function computeStartIndex(PlayerStoreMap playerStoreMap)
        public
        view
        override
        returns (uint8 startIdx)
    {
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

    function isSpecialMoveCard(WhotCard card) public view override returns (bool) {}

    function getCardAttributes(WhotCard card, uint256)
        /**
         * cardSize *
         */
        public
        view
        override
        returns (uint256 shape, uint256 cardNumber)
    {
        return (uint256(card.shape()), card.number());
    }

    function supportsCardSize(uint256 cardBitsSize) public pure override returns (bool) {
        return cardBitsSize == CARD_SIZE_8;
    }
}
