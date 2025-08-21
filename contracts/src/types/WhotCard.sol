// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

type WhotCard is uint8;

using WhotCardLib for WhotCard global;

library WhotCardLib {
    function toWhotCard(uint8 rawCard) internal pure returns (WhotCard) {
        return WhotCard.wrap(rawCard);
    }
}

using WhotCardStandardLibx8 for WhotCard;

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

    function shape(WhotCard card) internal pure returns (CardShape) {
        return CardShape(WhotCard.unwrap(card) >> 5);
    }

    function number(WhotCard card) internal pure returns (uint8) {
        // card.into?
        return WhotCard.unwrap(card) & 0x1F;
    }

    function matchNumber(WhotCard card1, WhotCard card2) internal pure returns (bool) {
        return card1.number() == card2.number();
    }

    function matchNumber(WhotCard card, uint8 cardNum) internal pure returns (bool) {
        return card.number() == cardNum;
    }

    function matchShape(WhotCard card1, WhotCard card2) internal pure returns (bool) {
        return card1.shape() == card2.shape();
    }

    function matchWhot(WhotCard card1, WhotCard card2) internal pure returns (bool) {
        return card2.empty()
            ? false
            : card1.empty() || card1.matchShape(card2) || card1.matchNumber(card2);
    }

    function matchShape(WhotCard card1, CardShape cardShape) internal pure returns (bool) {
        return card1.shape() == cardShape;
    }

    function generalMarket(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_FOURTEEN);
    }

    function pickTwo(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWO);
    }

    function pickThree(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_FIVE);
    }

    function pickFour(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWO) && card.matchShape(CardShape.Star);
    }

    function pick(WhotCard card) internal pure returns (bool) {
        return card.pickTwo() || card.pickThree() || card.pickFour();
    }

    function suspension(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_EIGHT);
    }

    function iWish(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_TWENTY);
    }

    function holdOn(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(CARD_NUMBER_ONE);
    }

    function empty(WhotCard card) internal pure returns (bool) {
        return card.matchNumber(ZERO);
    }

    function makeWhotWish(CardShape cardShape) internal pure returns (WhotCard) {
        return WhotCard.wrap((uint8(cardShape) << 5) | CARD_NUMBER_TWENTY);
    }
}
