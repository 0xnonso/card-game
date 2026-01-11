// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {externalEuint256} from "@fhevm/solidity/lib/FHE.sol";
import "solady/src/utils/LibBytes.sol";
import "solady/src/utils/LibSort.sol";

import {TrustedShuffleServiceV0 as TSS} from "../TrustedShuffleService.sol";
import {BaseManager} from "../base/BaseManager.sol";
import {EInputData, InputType} from "../base/EInputHandler.sol";

import {Constants} from "../helpers/Constants.sol";
import {ICardEngine} from "../interfaces/ICardEngine.sol";
import {IRuleset} from "../interfaces/IRuleset.sol";
import {Action, Card, PlayerScoreData} from "../libraries/CardEngineLib.sol";
import {WhotCardStandardLibx8 as WhotCard} from "../libraries/WhotCardDeck.sol";
import {Hook, HookPermissions} from "../types/Hook.sol";

contract WhotManager is BaseManager {
    TSS internal tss;
    mapping(uint256 gameId => GameSettings) internal gameSettings;
    mapping(uint256 gameId => address[]) internal winners;

    event GameEnded(uint256 indexed gameId, uint256[] sortedPackedData);

    struct GameSettings {
        bool isRouletteGame;
        bool isSuddenDeath;
    }

    constructor(ICardEngine _cardEngine, TSS _tss) BaseManager(_cardEngine) {
        tss = _tss;
    }

    function createGame(
        IRuleset ruleset,
        uint8 maxPlayers,
        uint8 handSize,
        address[] memory proposedPlayers,
        bool roulette,
        bool endAfterFirstExit
    ) external returns (uint256 gameId) {
        bytes memory proofData = tss.useInputProof();

        externalEuint256 handle0 = externalEuint256.wrap(bytes32(LibBytes.slice(proofData, 0, 32)));
        externalEuint256 handle1 = externalEuint256.wrap(bytes32(LibBytes.slice(proofData, 32, 64)));

        ICardEngine.CreateGameParams memory params;
        params.input0 = EInputData({inputType: InputType._EUINT256, externalInput: abi.encode(handle0)});
        params.input1 = EInputData({inputType: InputType._EUINT256, externalInput: abi.encode(handle1)});
        params.inputProof = LibBytes.slice(proofData, 64);
        params.gameRuleset = ruleset;
        params.cardBitSize = WhotCard.cardSize();
        params.cardDeckSize = WhotCard.getDefaultDeck().length;
        params.maxPlayers = maxPlayers;
        params.initialHandSize = handSize;
        params.hookPermissions =
            HookPermissions.wrap(Hook.ON_START_GAME_FLAG | Hook.ON_PLAYER_EXIT_FLAG | Hook.ON_FINISH_GAME_FLAG);
        params.proposedPlayers = proposedPlayers;

        gameId = CARD_ENGINE.createGame(params);

        gameSettings[gameId] = GameSettings({isRouletteGame: roulette, isSuddenDeath: endAfterFirstExit});
    }

    function getWinners(uint256 gameId) external view returns (address[] memory) {
        return winners[gameId];
    }

    function onStartGame(uint256 gameId) external view override onlyCardEngine returns (bool) {
        return gameSettings[gameId].isRouletteGame;
    }

    function onPlayerExit(uint256 gameId, address /**player**/, bool forfeited)
        external
        override
        onlyCardEngine
        returns (bool)
    {
        return !forfeited && gameSettings[gameId].isSuddenDeath;
    }

    function onFinishGame(
        uint256 gameId,
        IRuleset gameRuleset,
        PlayerScoreData[] calldata playersData,
        uint256[2] calldata
    ) external override onlyCardEngine {
        selectGameWinner(gameId, playersData, gameRuleset);
    }

    function selectGameWinner(uint256 gameId, PlayerScoreData[] calldata playersData, IRuleset gameRuleset) internal {
        uint256 dataLength = playersData.length;
        uint256[] memory packedData = new uint256[](dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            packedData[i] =
                calculatePlayerScore(playersData[i], gameRuleset) << 160 | uint256(uint160(playersData[i].playerAddr));
        }
        LibSort.insertionSort(packedData);
        uint256 firstWinner = packedData[0];
        winners[gameId].push(extractPlayerAddr(firstWinner));
        for (uint256 i = 1; i < dataLength; i++) {
            uint256 nextWinner = packedData[i];
            if ((firstWinner >> 160) != (nextWinner >> 160)) {
                break;
            }
            winners[gameId].push(extractPlayerAddr(nextWinner));
        }
        emit GameEnded(gameId, packedData);
    }

    function calculatePlayerScore(PlayerScoreData memory playerData, IRuleset ruleset)
        internal
        view
        returns (uint256 playerScore)
    {
        uint256 cardSize = playerData.deckMap.getDeckCardSize();
        for (uint256 i = 0; i < playerData.hand.length; i++) {
            Card card = playerData.hand[i];
            (, uint256 cardValue) = ruleset.getCardAttributes(card, cardSize);
            playerScore += cardValue;
        }
    }

    function extractPlayerAddr(uint256 packedData) internal pure returns (address playerAddr) {
        playerAddr = address(uint160(packedData & Constants.ADDRESS_MASK));
    }
}
