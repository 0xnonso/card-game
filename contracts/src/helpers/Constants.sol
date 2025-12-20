// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library Constants {
    uint256 constant U8_MASK = 0xff;
    uint256 constant U16_MASK = 0xffff;
    uint256 constant U40_MASK = 0xffffffffff;
    uint256 constant U64_MASK = 0xffffffffffffffff;
    uint256 constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    uint256 constant MAX_DELAY = 6 minutes;
    uint256 constant MAX_DECRYPT_DELAY = 3 minutes;
    // max number of players in a game.
    uint256 constant MIN_PLAYERS = 2;
    uint256 constant MAX_PLAYERS = 8;
    uint256 constant ALL_OTHER_PLAYERS = type(uint8).max;
}
