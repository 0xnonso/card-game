// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Card} from "../types/Card.sol";

using WhotCardStandardLibx8 for Card;

library WhotCardStandardLibx8 {
    uint8 private constant ZERO = 0;
    uint8 private constant CARD_NUMBER_ONE = 1;
    uint8 private constant CARD_NUMBER_TWO = 2;
    uint8 private constant CARD_NUMBER_FIVE = 5;
    uint8 private constant CARD_NUMBER_EIGHT = 8;
    uint8 private constant CARD_NUMBER_FOURTEEN = 14;
    uint8 private constant CARD_NUMBER_TWENTY = 20;

    enum CardShape {
        Circle,
        Triangle,
        Cross,
        Square,
        Star,
        Whot
    }

    function shape(Card card) internal pure returns (CardShape) {
        return CardShape(Card.unwrap(card) >> 5);
    }

    function number(Card card) internal pure returns (uint8) {
        return Card.unwrap(card) & 0x1F;
    }

    function matchNumber(Card card1, Card card2) internal pure returns (bool) {
        return card1.number() == card2.number();
    }

    function matchNumber(Card card, uint8 cardNum) internal pure returns (bool) {
        return card.number() == cardNum;
    }

    function matchShape(Card card1, Card card2) internal pure returns (bool) {
        return card1.shape() == card2.shape();
    }

    function matchWhot(Card card1, Card card2) internal pure returns (bool) {
        return card2.isEmpty()
            ? false
            : card1.isEmpty() || card1.matchShape(card2) || card1.matchNumber(card2) || card2.isWishCard();
    }

    function matchShape(Card card1, CardShape cardShape) internal pure returns (bool) {
        return card1.shape() == cardShape;
    }

    function isGeneralMarket(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_FOURTEEN);
    }

    function isPickTwo(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWO);
    }

    function isPickThree(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_FIVE);
    }

    function isPickFour(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWO) && card.matchShape(CardShape.Star);
    }

    function isPick(Card card) internal pure returns (bool) {
        return card.isPickTwo() || card.isPickThree() || card.isPickFour();
    }

    function isSuspension(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_EIGHT);
    }

    function isWishCard(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWENTY);
    }

    function isHoldOn(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_ONE);
    }

    function isEmpty(Card card) internal pure returns (bool) {
        return card.matchNumber(ZERO);
    }

    function makeWhotWish(CardShape cardShape) internal pure returns (Card) {
        return Card.wrap((uint8(cardShape) << 5) | CARD_NUMBER_TWENTY);
    }

    function cardSize() internal pure returns (uint256) {
        return 8;
    }
}
