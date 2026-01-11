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

    uint256 private constant WHOT_CARD_SIZE = 8;

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
        return WHOT_CARD_SIZE;
    }

    function getDefaultDeck() internal pure returns (Card[] memory deck) {
        Card[] memory WHOT_DECK = new Card[](54);
        // Circle
        WHOT_DECK[0] = Card.wrap(1);
        WHOT_DECK[1] = Card.wrap(2);
        WHOT_DECK[2] = Card.wrap(3);
        WHOT_DECK[3] = Card.wrap(4);
        WHOT_DECK[4] = Card.wrap(5);
        WHOT_DECK[5] = Card.wrap(7);
        WHOT_DECK[6] = Card.wrap(8);
        WHOT_DECK[7] = Card.wrap(10);
        WHOT_DECK[8] = Card.wrap(11);
        WHOT_DECK[9] = Card.wrap(12);
        WHOT_DECK[10] = Card.wrap(13);
        WHOT_DECK[11] = Card.wrap(14);
        // Triangle
        WHOT_DECK[12] = Card.wrap(33);
        WHOT_DECK[13] = Card.wrap(34);
        WHOT_DECK[14] = Card.wrap(35);
        WHOT_DECK[15] = Card.wrap(37);
        WHOT_DECK[16] = Card.wrap(39);
        WHOT_DECK[17] = Card.wrap(42);
        WHOT_DECK[18] = Card.wrap(43);
        WHOT_DECK[19] = Card.wrap(45);
        WHOT_DECK[20] = Card.wrap(46);
        // Cross
        WHOT_DECK[21] = Card.wrap(65);
        WHOT_DECK[22] = Card.wrap(66);
        WHOT_DECK[23] = Card.wrap(67);
        WHOT_DECK[24] = Card.wrap(68);
        WHOT_DECK[25] = Card.wrap(69);
        WHOT_DECK[26] = Card.wrap(71);
        WHOT_DECK[27] = Card.wrap(72);
        WHOT_DECK[28] = Card.wrap(74);
        WHOT_DECK[29] = Card.wrap(75);
        WHOT_DECK[30] = Card.wrap(76);
        WHOT_DECK[31] = Card.wrap(77);
        WHOT_DECK[32] = Card.wrap(78);
        // Square
        WHOT_DECK[33] = Card.wrap(97);
        WHOT_DECK[34] = Card.wrap(98);
        WHOT_DECK[35] = Card.wrap(99);
        WHOT_DECK[36] = Card.wrap(101);
        WHOT_DECK[37] = Card.wrap(103);
        WHOT_DECK[38] = Card.wrap(106);
        WHOT_DECK[39] = Card.wrap(107);
        WHOT_DECK[40] = Card.wrap(109);
        WHOT_DECK[41] = Card.wrap(110);
        // Star
        WHOT_DECK[42] = Card.wrap(129);
        WHOT_DECK[43] = Card.wrap(130);
        WHOT_DECK[44] = Card.wrap(131);
        WHOT_DECK[45] = Card.wrap(132);
        WHOT_DECK[46] = Card.wrap(133);
        WHOT_DECK[47] = Card.wrap(135);
        WHOT_DECK[48] = Card.wrap(136);
        // Whot
        WHOT_DECK[49] = Card.wrap(180);
        WHOT_DECK[50] = Card.wrap(180);
        WHOT_DECK[51] = Card.wrap(180);
        WHOT_DECK[52] = Card.wrap(180);
        WHOT_DECK[53] = Card.wrap(180);

        return WHOT_DECK;
    }
}
