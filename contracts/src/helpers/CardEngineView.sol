// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {euint256} from "@fhevm/solidity/lib/FHE.sol";

import {IExtsload} from "../interfaces/IExtsload.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action, GameStatus, PlayerData} from "../libraries/CardEngineLib.sol";
import {CacheValue, GameDataPositions as GDP, PlayerDataPositions as PDP} from "../types/Cache.sol";
import {Card} from "../types/Card.sol";
import {HookPermissions} from "../types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";

contract CardEngineView {
    IExtsload public immutable CARD_ENGINE;

    uint256 internal constant GAME_DATA_SLOT = 2;
    uint256 internal constant PLAYER_DATA_OFFSET = 4;

    constructor(address cardEngine) {
        CARD_ENGINE = IExtsload(cardEngine);
    }

    function computeGameDataSlot(uint256 gameId) internal pure returns (uint256 slot) {
        assembly {
            mstore(0x00, gameId)
            mstore(0x20, GAME_DATA_SLOT)
            slot := keccak256(0x00, 0x40)
        }
    }

    function computePlayerDataSlot(uint256 gameId, uint256 playerIndex) internal pure returns (uint256 slot) {
        uint256 gameSlot = computeGameDataSlot(gameId);
        assembly {
            mstore(0x00, add(gameSlot, PLAYER_DATA_OFFSET))
            slot := add(keccak256(0x00, 0x20), mul(playerIndex, 0x03))
        }
    }

    function getPlayerData(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (
            address playerAddr,
            DeckMap playerDeckMap,
            uint8 pendingAction,
            bool forfeited,
            euint256[2] memory playerHand
        )
    {
        uint256 slot = computePlayerDataSlot(gameId, playerIndex);
        uint256[] memory values = CARD_ENGINE.extsload(slot, 3);

        CacheValue value0 = CacheValue.wrap(values[0]);

        playerAddr = value0.loadAddress(PDP.PLAYER_ADDRESS);
        playerDeckMap = DeckMap.wrap(value0.loadU72(PDP.DECKMAP));
        pendingAction = value0.loadU8(PDP.PENDING_ACTION);
        forfeited = value0.loadU8(PDP.FORFEITED) != 0;
        playerHand[0] = euint256.wrap(bytes32(values[1]));
        playerHand[1] = euint256.wrap(bytes32(values[2]));
    }

    function getGameData(uint256 gameId)
        external
        view
        returns (
            address gameCreator,
            Card callCard,
            uint8 playerTurnIdx,
            GameStatus status,
            uint40 lastMoveTimestamp,
            uint8 playersLeftToJoin,
            HookPermissions hookPermissions,
            PlayerStoreMap playerStoreMap,
            IRuleset ruleset,
            DeckMap marketDeckMap,
            uint8 initialHandSize
        )
    {
        uint256 slot = computeGameDataSlot(gameId);
        uint256[] memory values = CARD_ENGINE.extsload(slot, 2);

        CacheValue value = CacheValue.wrap(values[0]);

        gameCreator = value.loadAddress(GDP.GAME_CREATOR);
        callCard = Card.wrap(value.loadU8(GDP.CALL_CARD));
        playerTurnIdx = value.loadU8(GDP.PLAYER_TURN_INDEX);
        status = GameStatus(value.loadU8(GDP.STATUS));
        lastMoveTimestamp = value.loadU40(GDP.LAST_MOVE_TIMESTAMP);
        hookPermissions = HookPermissions.wrap(value.loadU8(GDP.HOOK_PERMISSIONS));
        playerStoreMap = PlayerStoreMap.wrap(value.loadU8(GDP.PLAYER_STORE_MAP));

        value = CacheValue.wrap(values[1]);

        ruleset = IRuleset(value.loadAddress(GDP.RULESET));
        marketDeckMap = DeckMap.wrap(value.loadU72(GDP.MARKET_DECK_MAP));
        initialHandSize = value.loadU8(GDP.INITIAL_HAND_SIZE);
        playersLeftToJoin = value.loadU8(GDP.PLAYERS_LEFT_TO_JOIN);
    }
}
