// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRNG} from "../interfaces/IRNG.sol";
import {IRuleset} from "../interfaces/IRuleSet.sol";
import {Action as GameAction, PendingAction as GamePendingAction} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {Card, WhotCardStandardLibx8} from "../types/Card.sol";
import {PlayerStoreMap} from "../types/Map.sol";

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint256} from "@fhevm/solidity/lib/FHE.sol";

import "hardhat/console.sol";

// This contract contains the rules for the Whot game.
// It includes functions to validate moves, check game state, etc.
contract WhotRuleset is IRuleset, SepoliaConfig {
    using ConditionalsLib for *;
    using WhotCardStandardLibx8 for Card;

    uint256 constant CARD_SIZE_8 = 8;
    IRNG internal rng;

    constructor(address _rng) {
        rng = IRNG(_rng);
    }

    // Example function to validate a move
    function resolveMove(ResolveMoveParams memory params) public returns (Effect memory effect) {
        Action[] memory actionsToExec = new Action[](1);
        if (params.gameAction.eqs(GameAction.Play)) {
            if (!params.callCard.matchWhot(params.card)) {
                revert("Cards dont match");
            }
            effect.callCard = params.callCard;
            if (params.card.pickTwo()) {
                if (params.card.pickFour() && params.isSpecial) {
                    actionsToExec[0].op = EngineOp.PickPendingFour;
                } else {
                    actionsToExec[0].op = EngineOp.PickPendingTwo;
                }
                uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                actionsToExec[0].againstPlayerIndex = nextTurn; // Set turn to 1 for pick action
                effect.nextPlayerIndex = nextTurn;
            } else if (params.card.pickThree() && params.isSpecial) {
                actionsToExec[0].op = EngineOp.PickPendingThree;
                uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                actionsToExec[0].againstPlayerIndex = nextTurn;
                effect.nextPlayerIndex = nextTurn;
            } else if (params.card.holdOn()) {
                PlayerStoreMap playerStoreMap = params.playerStoreMap;
                effect.nextPlayerIndex =
                    playerStoreMap.getNextIndexFrom_RL(playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex)); // Set turn to 1 for hold on op
            } else if (params.card.suspension()) {
                effect.nextPlayerIndex = params.currentPlayerIndex; // Set turn to 0 for suspension op
            } else if (params.card.generalMarket()) {
                actionsToExec[0].op = EngineOp.PickOne;
                actionsToExec[0].againstPlayerIndex = type(uint8).max; // Set turn to 0 for general market op
                effect.nextPlayerIndex = params.currentPlayerIndex;
            } else if (params.card.iWish()) {
                (WhotCardStandardLibx8.CardShape wishShape) =
                    abi.decode(params.extraData, (WhotCardStandardLibx8.CardShape));
                effect.callCard = WhotCardStandardLibx8.makeWhotWish(wishShape);
            } else {
                uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
                effect.nextPlayerIndex = nextTurn; // Normal play, just advance turn
            }
        } else if (params.gameAction.eqs(GameAction.Defend)) {
            if (!params.isSpecial) {
                revert(); //revert DefenseNotEnabled();
            }
            uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
            if (params.pendingAction == 4) {
                actionsToExec[0].op = EngineOp.PickTwo;
                actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
            }
            effect.nextPlayerIndex = nextTurn;
        } else if (params.gameAction.eqs(GameAction.Draw)) {
            actionsToExec[0].op = EngineOp.PickOne;
            actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
            uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
            effect.nextPlayerIndex = nextTurn; // Normal play, just advance turn
        } else if (params.gameAction.eqs(GameAction.Pick)) {
            actionsToExec[0].op = EngineOp(params.pendingAction % 8);
            actionsToExec[0].againstPlayerIndex = params.currentPlayerIndex;
            uint8 nextTurn = params.playerStoreMap.getNextIndexFrom_RL(params.currentPlayerIndex);
            effect.nextPlayerIndex = nextTurn; // Normal play, just advance turn
        }
        effect.actions = actionsToExec;
    }

    function computeStartIndex(PlayerStoreMap playerStoreMap) public view returns (uint8 startIdx) {
        // return uint8(rng.generatePseudoRandomNumber() % playerStoreMap.len());
    }

    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        public
        pure
        returns (uint8 nextTurnIdx)
    {
        return playerStoreMap.getNextIndexFrom_RL(uint8(currentPlayerIndex));
    }

    function isSpecialMoveCard(Card card) public pure returns (bool) {}

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
        return cardBitsSize == CARD_SIZE_8;
    }
}
