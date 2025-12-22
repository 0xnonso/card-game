// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRuleset} from "../../src/interfaces/IRuleset.sol";
import {Card} from "../../src/types/Card.sol";
import {PlayerStoreMap} from "../../src/types/Map.sol";

import {Action as GameAction} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {WhotCardStandardLibx8 as WhotCard} from "../libraries/WhotCardDeck.sol";

/**
 * Minimal ruleset for testing: accepts any 8-bit card, does not enforce
 * game rules, and simply advances to the next player each move.
 */
contract MockRuleset is IRuleset {
    using ConditionalsLib for *;
    using WhotCard for Card;

    address public immutable cardEngine;

    constructor(address _cardEngine) {
        cardEngine = _cardEngine;
    }

    modifier onlyCardEngine() {
        require(msg.sender == cardEngine, "MockRuleset: not card engine");
        _;
    }

    function resolveMove(ResolveMoveParams calldata params)
        external
        view
        onlyCardEngine
        returns (Effect memory effect)
    {
        effect.actions = new Action[](0);
        effect.callCard = params.card;
        effect.nextPlayerIndex = params.playerStoreMap.getNextIndex(params.currentPlayerIndex);
        if (params.action.eqs(GameAction.Draw)) {
            effect.actions = new Action[](1);
            effect.actions[0].op = EngineOp.DealOne;
            effect.actions[0].againstPlayerIndex = params.currentPlayerIndex;
        }
    }

    function afterResolveMove(ResolveMoveParams calldata) external view onlyCardEngine {}

    function computeStartIndex(PlayerStoreMap playerStoreMap) external pure returns (uint8 startIndex) {}

    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        external
        pure
        returns (uint8 nextPlayerIndex)
    {
        nextPlayerIndex = playerStoreMap.getNextIndex(uint8(currentPlayerIndex));
    }

    function isSpecialMoveCard(Card) external pure returns (bool) {
        return false;
    }

    function getCardAttributes(Card card, uint256 /*cardSize*/ ) public pure returns (uint256, uint256) {
        return (uint256(card.shape()), card.number());
    }

    function supportsCardSize(uint256 cardSize) external pure returns (bool) {
        return cardSize <= 8;
    }
}
