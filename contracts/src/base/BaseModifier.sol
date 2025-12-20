// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ICardEngine} from "../interfaces/ICardEngine.sol";

contract BaseModifier {
    ICardEngine public immutable CARD_ENGINE;

    error BaseModifier_OnlyCardEngine();

    modifier onlyCardEngine() {
        if (msg.sender != address(CARD_ENGINE)) {
            revert BaseModifier_OnlyCardEngine();
        }
        _;
    }

    constructor(ICardEngine _cardEngine) {
        CARD_ENGINE = ICardEngine(_cardEngine);
    }
}
