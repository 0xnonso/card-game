// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FHE, euint256} from "@fhevm/solidity/lib/FHE.sol";

import {ICardEngine} from "../../src/interfaces/ICardEngine.sol";
import {IRuleset} from "../../src/interfaces/IRuleset.sol";
import {Action} from "../../src/libraries/CardEngineLib.sol";
import {WhotCardStandardLibx8 as WhotCard} from "../../src/libraries/WhotCardDeck.sol";

import {MockRNG} from "../../src/mocks/MockRNG.sol";
import {WhotRuleset} from "../../src/rules/WhotRuleset.sol";
import {DeckMap, PlayerStoreMap} from "../../src/types/Map.sol";

import "forge-std/Test.sol";

contract WhotRulesetTest is Test {
    ICardEngine cardEngine;
    WhotRuleset ruleset;
    MockRNG mockRNG;

    // function setUp() public {
    //     cardEngine = ICardEngine(0x77EC3eBe97AE4A7310C58B563B9fE7D417bA99f2);
    //     mockRNG = new MockRNG(uint256(keccak256("WHOT_RULESET_TEST")));
    //     ruleset = new WhotRuleset(address(mockRNG), cardEngine);
    // }

    // function test_PickTwo() internal {
    //     IRuleset.ResolveMoveParams memory moveParams;
    //     moveParams.action = Action.Play;
    //     moveParams.callCard = WhotCard.getDefaultDeck()[1];
    //     moveParams.currentPlayerIndex = 1;
    //     moveParams.playerStoreMap = PlayerStoreMap.wrap(510); // 111111110
    //     moveParams.cardSize = WhotCard.cardSize();
    // }
}
