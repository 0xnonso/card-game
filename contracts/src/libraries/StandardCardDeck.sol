// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Card} from "../types/Card.sol";

using Standard52CardDeckLibx6 for Card;

library Standard52CardDeckLibx6 {
    enum Suit {
        Clubs,
        Diamonds,
        Hearts,
        Spades
    }

    uint8 private constant ZERO = 0;
    uint8 private constant RANK_ACE = 1;
    uint8 private constant RANK_JACK = 11;
    uint8 private constant RANK_QUEEN = 12;
    uint8 private constant RANK_KING = 13;

    uint256 private constant STANDARD_52_CARD_SIZE = 6;

    function suit(Card card) internal pure returns (Suit) {
        return Suit(Card.unwrap(card) >> 4);
    }

    function rank(Card card) internal pure returns (uint8) {
        return Card.unwrap(card) & 0xF;
    }

    function matchRank(Card card1, Card card2) internal pure returns (bool) {
        return card1.rank() == card2.rank();
    }

    function matchRank(Card card, uint8 _rank) internal pure returns (bool) {
        return card.rank() == _rank;
    }

    function matchSuit(Card card1, Card card2) internal pure returns (bool) {
        return card1.suit() == card2.suit();
    }

    function matchSuit(Card card, Suit _suit) internal pure returns (bool) {
        return card.suit() == _suit;
    }

    function isFaceCard(Card card) internal pure returns (bool _isFaceCard) {
        uint8 r = card.rank();
        assembly {
            _isFaceCard := or(or(eq(r, RANK_JACK), eq(r, RANK_QUEEN)), eq(RANK_KING, 13))
        }
    }

    function isNumberCard(Card card) internal pure returns (bool _isNumberCard) {
        uint8 r = card.rank();
        assembly {
            _isNumberCard := and(lt(r, RANK_JACK), gt(r, 0))
        }
    }

    function isAce(Card card) internal pure returns (bool) {
        return card.matchRank(RANK_ACE);
    }

    function isKing(Card card) internal pure returns (bool) {
        return card.matchRank(RANK_KING);
    }

    function isQueen(Card card) internal pure returns (bool) {
        return card.matchRank(RANK_QUEEN);
    }

    function isJack(Card card) internal pure returns (bool) {
        return card.matchRank(RANK_JACK);
    }

    function isEmpty(Card card) internal pure returns (bool) {
        return card.matchRank(ZERO);
    }

    function cardSize() internal pure returns (uint256) {
        return STANDARD_52_CARD_SIZE;
    }

    function defaultDeck() internal pure returns (Card[] memory) {
        Card[] memory deck = new Card[](52);
        // Clubs
        deck[0] = Card.wrap(1);
        deck[1] = Card.wrap(2);
        deck[2] = Card.wrap(3);
        deck[3] = Card.wrap(4);
        deck[4] = Card.wrap(5);
        deck[5] = Card.wrap(6);
        deck[6] = Card.wrap(7);
        deck[7] = Card.wrap(8);
        deck[8] = Card.wrap(9);
        deck[9] = Card.wrap(10);
        deck[10] = Card.wrap(11);
        deck[11] = Card.wrap(12);
        deck[12] = Card.wrap(13);
        // Diamonds
        deck[13] = Card.wrap(17);
        deck[14] = Card.wrap(18);
        deck[15] = Card.wrap(19);
        deck[16] = Card.wrap(20);
        deck[17] = Card.wrap(21);
        deck[18] = Card.wrap(22);
        deck[19] = Card.wrap(23);
        deck[20] = Card.wrap(24);
        deck[21] = Card.wrap(25);
        deck[22] = Card.wrap(26);
        deck[23] = Card.wrap(27);
        deck[24] = Card.wrap(28);
        deck[25] = Card.wrap(29);
        // Hearts
        deck[26] = Card.wrap(33);
        deck[27] = Card.wrap(34);
        deck[28] = Card.wrap(35);
        deck[29] = Card.wrap(36);
        deck[30] = Card.wrap(37);
        deck[31] = Card.wrap(38);
        deck[32] = Card.wrap(39);
        deck[33] = Card.wrap(40);
        deck[34] = Card.wrap(41);
        deck[35] = Card.wrap(42);
        deck[36] = Card.wrap(43);
        deck[37] = Card.wrap(44);
        deck[38] = Card.wrap(45);
        // Spades
        deck[39] = Card.wrap(49);
        deck[40] = Card.wrap(50);
        deck[41] = Card.wrap(51);
        deck[42] = Card.wrap(52);
        deck[43] = Card.wrap(53);
        deck[44] = Card.wrap(54);
        deck[45] = Card.wrap(55);
        deck[46] = Card.wrap(56);
        deck[47] = Card.wrap(57);
        deck[48] = Card.wrap(58);
        deck[49] = Card.wrap(59);
        deck[50] = Card.wrap(60);
        deck[51] = Card.wrap(61);

        return deck;
    }
}
