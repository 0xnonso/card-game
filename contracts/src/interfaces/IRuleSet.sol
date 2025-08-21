// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Action as GameAction, PendingAction as GamePendingAction} from "../libraries/WhotLib.sol";
import {PlayerStoreMap} from "../types/Map.sol";
import {WhotCard} from "../types/WhotCard.sol";

interface IRuleSet {
    enum Action {
        None,
        PickOne,
        PickTwo,
        PickThree,
        PickFour,
        PickFive,
        PickSix,
        PickSeven,
        PickEight,
        PickPendingOne,
        PickPendingTwo,
        PickPendingThree,
        PickPendingFour,
        PickPendingFive,
        PickPendingSix,
        PickPendingSeven,
        PickPendingEight
    }
    // HoldOn
    // Suspension,
    // GeneralMarket

    struct MoveValidationResult {
        Action action;
        WhotCard callCard;
        uint8 againstPlayerIndex;
        uint8 nextPlayerIndex;
    }

    struct MoveValidationParams {
        GameAction gameAction;
        GamePendingAction pendingAction;
        WhotCard card;
        WhotCard callCard;
        uint256 cardSize;
        uint8 currentPlayerIndex;
        PlayerStoreMap playerStoreMap;
        bool isSpecial;
        bytes extraData;
    }

    function validateMove(MoveValidationParams memory params)
        external
        view
        returns (MoveValidationResult memory);

    function computeStartIndex(PlayerStoreMap playerStoreMap)
        external
        view
        returns (uint8 startIndex);

    function computeNextTurnIndex(PlayerStoreMap playerStoreMap, uint256 currentPlayerIndex)
        external
        view
        returns (uint8 nextPlayerIndex);

    function isSpecialMoveCard(WhotCard card) external view returns (bool);

    function getCardAttributes(WhotCard card, uint256 cardSize)
        external
        view
        returns (uint256 shape, uint256 cardNumber);

    function supportsCardSize(uint256 cardSize) external view returns (bool);
}
