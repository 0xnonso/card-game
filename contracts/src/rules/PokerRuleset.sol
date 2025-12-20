// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseModifier} from "../base/BaseModifier.sol";

import {ICardEngine} from "../interfaces/ICardEngine.sol";
import {IRNG} from "../interfaces/IRNG.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action as GameAction} from "../libraries/CardEngineLib.sol";
import {ConditionalsLib} from "../libraries/ConditionalsLib.sol";
import {Standard52CardDeckLibx6} from "../libraries/StandardCardDeck.sol";
import {Card} from "../types/Card.sol";
import {PlayerStoreMap} from "../types/Map.sol";

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint256} from "@fhevm/solidity/lib/FHE.sol";

// import "hardhat/console.sol";

contract PokerRuleset is BaseModifier, IRuleset {
    using ConditionalsLib for *;
    using Standard52CardDeckLibx6 for Card;

    IRNG internal rng;

    constructor(address _rng, ICardEngine _cardEngine) BaseModifier(_cardEngine) {
        rng = IRNG(_rng);
    }

    function resolveMove(ResolveMoveParams memory params) public onlyCardEngine returns (Effect memory effect) {
        if (params.playerDeckMap.len() != 2) {
            revert();
        }
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

    function isSpecialMoveCard(Card) public pure returns (bool) {
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
