// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

type Card is uint8;

using CardLib for Card global;

library CardLib {
    function toCard(uint8 rawCard) internal pure returns (Card) {
        return Card.wrap(rawCard);
    }
}
