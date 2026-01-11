// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseManager} from "../base/BaseManager.sol";

import {ICardEngine} from "../interfaces/ICardEngine.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action, Card} from "../libraries/CardEngineLib.sol";

contract PokerManager is BaseManager {
    struct CommunityHand {
        Card communityCard0;
        bool decryptedCard0;
        Card communityCard1;
        bool decryptedCard1;
        Card communityCard2;
        bool decryptedCard2;
    }

    constructor(ICardEngine _cardEngine) BaseManager(_cardEngine) {}

    function onExecuteAction(uint256 gameId, address player, Card playingCard, Action action) external onlyCardEngine {
        if (player != address(this)) {
            revert("only poker manager");
        }
    }

    function revealCard(uint256 gameId) external {}

    function handleRevealCard(uint256 requestId, bytes memory clearTexts, bytes memory signatures) external {}
}
