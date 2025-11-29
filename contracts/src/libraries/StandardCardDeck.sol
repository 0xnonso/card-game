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

    uint8 private constant RANK_ACE = 1;
    uint8 private constant RANK_JACK = 11;
    uint8 private constant RANK_QUEEN = 12;
    uint8 private constant RANK_KING = 13;

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
        return card.matchRank(0);
    }

    function cardSize() internal pure returns (uint256) {
        return 6;
    }
}
