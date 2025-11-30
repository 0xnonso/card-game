// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ICardEngine} from "../interfaces/ICardEngine.sol";

contract BaseModifier {
    ICardEngine public immutable cardEngine;

    error BaseModifier_OnlyCardEngine();

    modifier onlyCardEngine() {
        if (msg.sender != address(cardEngine)) {
            revert BaseModifier_OnlyCardEngine();
        }
        _;
    }

    constructor(ICardEngine _cardEngine) {
        cardEngine = ICardEngine(_cardEngine);
    }
}
