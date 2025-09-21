// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

type Card is uint8;

using CardLib for Card global;

library CardLib {
    function toCard(uint8 rawCard) internal pure returns (Card) {
        return Card.wrap(rawCard);
    }
}

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
        return card2.empty() ? false : card1.empty() || card1.matchShape(card2) || card1.matchNumber(card2);
    }

    function matchShape(Card card1, CardShape cardShape) internal pure returns (bool) {
        return card1.shape() == cardShape;
    }

    function generalMarket(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_FOURTEEN);
    }

    function pickTwo(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWO);
    }

    function pickThree(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_FIVE);
    }

    function pickFour(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWO) && card.matchShape(CardShape.Star);
    }

    function pick(Card card) internal pure returns (bool) {
        return card.pickTwo() || card.pickThree() || card.pickFour();
    }

    function suspension(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_EIGHT);
    }

    function iWish(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWENTY);
    }

    function holdOn(Card card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_ONE);
    }

    function empty(Card card) internal pure returns (bool) {
        return card.matchNumber(ZERO);
    }

    function makeWhotWish(CardShape cardShape) internal pure returns (Card) {
        return Card.wrap((uint8(cardShape) << 5) | CARD_NUMBER_TWENTY);
    }
}
