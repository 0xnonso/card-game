// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseModifier} from "../base/BaseModifier.sol";
import {ICardEngine} from "../interfaces/ICardEngine.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action as GameAction} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {Standard52CardDeckLibx6} from "../libraries/StandardCardDeck.sol";

import {Card} from "../types/Card.sol";
import {PlayerStoreMap} from "../types/Map.sol";

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint256} from "@fhevm/solidity/lib/FHE.sol";


contract BlackJackRulesetPvH is BaseModifier, IRuleset, ZamaEthereumConfig {
    using ConditionalsLib for *;
    using Standard52CardDeckLibx6 for Card;

    mapping (uint256 gameId => BlackJackScore) internal blackJack;

    // enum Step {}

    struct BlackJackScore {
        uint8 dealerScore;
        uint8 playerScore;
    }

    constructor(ICardEngine _cardEngine) BaseModifier(_cardEngine) {}

    function resolveMove(ResolveMoveParams memory params) public onlyCardEngine returns (Effect memory effect) {

    }

    function afterResolveMove(ResolveMoveParams memory params) public onlyCardEngine {}

    function computeStartIndex(PlayerStoreMap playerStoreMap) public view returns (uint8 startIdx) {
        return 0;
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
    {}

    function supportsCardSize(uint256 cardBitsSize) public pure returns (bool) {}
}
