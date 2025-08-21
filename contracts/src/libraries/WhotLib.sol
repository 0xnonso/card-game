// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FHE, euint256, euint8} from "fhevm/lib/FHE.sol";

import {IRuleSet} from "../interfaces/IRuleSet.sol";
import {PlayerStoreMap, WhotDeckMap} from "../types/Map.sol";
import {WhotCard, WhotCardLib} from "../types/WhotCard.sol";

enum Action {
    Play,
    Defend,
    GoToMarket,
    Pick
}

enum PendingAction {
    None,
    PickOne,
    PickTwo,
    PickThree,
    PickFour,
    PickFive,
    PickSix,
    PickSeven,
    PickEight
}

enum GameStatus {
    None,
    Started,
    Ended
}

struct PlayerData {
    address playerAddr;
    WhotDeckMap deckMap;
    PendingAction pendingAction;
    uint16 score;
    euint256[2] whotCardDeck;
}

struct GameData {
    address gameCreator;
    WhotCard callCard;
    uint8 playerTurnIdx;
    GameStatus status;
    uint40 lastMoveTimestamp;
    // maxPlayers | playersLeftToJoin;
    uint8 packedJoinCapacity;
    uint8 initialHandSize;
    PlayerStoreMap playerStoreMap;
    IRuleSet ruleSet;
    WhotDeckMap marketDeckMap;
    euint256[2] marketDeck;
    PlayerData[] players;
    mapping(address => bool) isProposedPlayer;
    // Allows for easier retrieval of player's data index;
    mapping(address => uint256) playerIndex;
}

using WhotLib for GameData global;
using WhotLib for PlayerData global;

library WhotLib {
    using FHE for *;

    error CardIndexOutOfBounds(uint256);
    error CardIndexIsEmpty(uint256);

    uint16 constant MAX_UINT16 = type(uint16).max;

    function isPlayerActive(GameData storage $, address playerAddr, PlayerStoreMap playerStoreMap)
        internal
        view
        returns (bool)
    {
        uint256 playerIdx = $.playerIndex[playerAddr];
        if (playerIdx == 0 && playerStoreMap.isMapEmpty()) return false;

        return $.players[playerIdx].playerAddr == playerAddr;
    }

    function getPlayerIndex(GameData storage $, address player) internal view returns (uint256) {
        return $.playerIndex[player];
    }

    function setPlayerScoreToMin(GameData storage $, uint256 index) internal {
        $.players[index].score = MAX_UINT16;
    }

    function calculateAndSetPlayerScore(
        GameData storage $,
        uint256 playerIndex,
        uint256[2] memory marketDeck
    ) internal {
        PlayerData memory player = $.players[playerIndex];
        WhotDeckMap playerDeckMap = player.deckMap;
        uint256[] memory cardIndexes = playerDeckMap.getNonEmptyIdxs();

        WhotDeckMap marketDeckMap = $.marketDeckMap;
        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardSize;
        uint16 total = 0;
        for (uint256 i = 0; i < cardIndexes.length; i++) {
            uint256 marketDeckIdx = cardIndexes[i];
            uint256 mask = (uint256(1) << cardSize) - 1;
            uint256 rawCard = marketDeck[marketDeckIdx / numCardsIn0]
                >> ((marketDeckIdx % numCardsIn0) * cardSize) & mask;
            WhotCard card = WhotCardLib.toWhotCard(uint8(rawCard));
            (, uint256 cardNumber) = $.ruleSet.getCardAttributes(card, cardSize);
            total += uint16(cardNumber);
        }

        $.players[playerIndex].score = total;
    }

    function getCardToCommit(GameData storage $, PlayerData memory p, uint256 cardIdx)
        internal
        returns (euint8)
    {
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardSize;
        if (cardIdx > (numCardsIn0 - 1)) revert CardIndexOutOfBounds(cardIdx);
        if (marketDeckMap.isNotEmpty(cardIdx) || p.deckMap.isEmpty(cardIdx)) {
            revert CardIndexIsEmpty(cardIdx);
        }

        euint256 marketDeck = $.marketDeck[cardIdx / numCardsIn0];
        uint256 mask = (uint256(1) << cardSize) - 1;
        euint8 cardToCommit =
            marketDeck.shr(uint8((cardIdx % numCardsIn0) * cardSize)).and(mask).asEuint8();
        FHE.allowThis(cardToCommit);
        return cardToCommit;
    }

    function addPlayer(GameData storage $, address player, PlayerStoreMap playerStoreMap)
        internal
        returns (PlayerStoreMap)
    {
        PlayerData memory pData;
        pData.playerAddr = player;

        pData.whotCardDeck[0] = FHE.asEuint256(0);
        pData.whotCardDeck[1] = FHE.asEuint256(0);

        FHE.allow(pData.whotCardDeck[0], player);
        FHE.allowThis(pData.whotCardDeck[0]);
        FHE.allow(pData.whotCardDeck[1], player);
        FHE.allowThis(pData.whotCardDeck[1]);

        uint256 playerIndex = $.players.length;
        $.players.push(pData);
        $.playerIndex[pData.playerAddr] = playerIndex;

        return playerStoreMap.addPlayer(playerIndex);
    }

    function initializeMarketDeckMap(uint256 marketDeckLen, uint256 deckCardBitSize)
        internal
        pure
        returns (WhotDeckMap)
    {
        uint64 mapMetaData = uint64((deckCardBitSize << 4) | (marketDeckLen & 0xf));
        return WhotDeckMap.wrap(uint64(((uint256(1) << marketDeckLen) - 1) << 8) + mapMetaData);
    }

    function initializePlayerStoreMap(uint256 numProposedPlayers)
        internal
        pure
        returns (PlayerStoreMap)
    {
        return PlayerStoreMap.wrap(uint16(numProposedPlayers & 0x0f) << 4);
    }

    function emptyDeckMapAtIndex(PlayerData memory p, uint256 cardIdx)
        internal
        pure
        returns (WhotDeckMap)
    {
        return p.deckMap.setToEmpty(cardIdx);
    }

    function dealInitialHand(
        GameData storage $,
        PlayerData memory p,
        uint256 index,
        uint256 numPlayers,
        uint256 handSize
    ) internal {
        uint256[] memory idxs = new uint256[](handSize);

        for (uint256 i = 0; i < idxs.length; i++) {
            idxs[i] = index + (i * numPlayers);
        }

        WhotDeckMap marketDeckMap = $.marketDeckMap;
        WhotDeckMap playerDeckMap;
        ($.marketDeckMap, playerDeckMap) = marketDeckMap.deal(p.deckMap, idxs);
        $.players[index].deckMap = playerDeckMap;

        euint256[2] memory marketDeck = $.marketDeck;

        uint256[2] memory mask = playerDeckMap.computeMask();
        p.whotCardDeck[0] = marketDeck[0].and(mask[0]);
        p.whotCardDeck[1] = marketDeck[1].and(mask[1]);

        $.players[index].whotCardDeck[0] = p.whotCardDeck[0];
        FHE.allow(p.whotCardDeck[0], p.playerAddr);
        FHE.allowThis(p.whotCardDeck[0]);

        $.players[index].whotCardDeck[1] = p.whotCardDeck[1];
        FHE.allow(p.whotCardDeck[1], p.playerAddr);
        FHE.allowThis(p.whotCardDeck[1]);
    }

    function deal(GameData storage $, PlayerData memory p, uint256 currentIdx) internal {
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        uint256 numCardsIn0 = 256 / marketDeckMap.getDeckCardSize();

        if (marketDeckMap.isMapNotEmpty()) {
            uint256 cardIdx;

            ($.marketDeckMap, $.players[currentIdx].deckMap, cardIdx) =
                marketDeckMap.deal(p.deckMap);

            uint256 i = cardIdx / numCardsIn0;
            uint256 mask = p.deckMap.computeMask()[i];
            euint256 updatedWhotCardDeck = $.marketDeck[i].and(mask);
            $.players[currentIdx].whotCardDeck[i] = updatedWhotCardDeck;
            FHE.allow(updatedWhotCardDeck, p.playerAddr);
            FHE.allowThis(updatedWhotCardDeck);
        }
    }

    function dealPickN(GameData storage $, PlayerData memory p, uint256 currentIdx, uint256 n)
        internal
    {
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        uint256 numCardsIn0 = 256 / marketDeckMap.getDeckCardSize();
        euint256[2] memory marketDeck = $.marketDeck;

        bool allow0;
        bool allowBothIdx;

        for (uint256 i = 0; i < n; i++) {
            if (marketDeckMap.isMapNotEmpty()) {
                uint256 cardIdx;
                (marketDeckMap, p.deckMap, cardIdx) = marketDeckMap.deal(p.deckMap);

                assembly ("memory-safe") {
                    let allow := iszero(div(cardIdx, numCardsIn0))
                    allow0 := or(allow, allow0)
                    allowBothIdx := xor(allow, allow0)
                }
            }
        }

        uint256[2] memory mask = p.deckMap.computeMask();
        euint256 playerDeck0;
        euint256 playerDeck1;

        if (allowBothIdx) {
            playerDeck0 = marketDeck[0].and(mask[0]);
            playerDeck1 = marketDeck[1].and(mask[1]);
            p.whotCardDeck[0] = playerDeck0;
            p.whotCardDeck[1] = playerDeck1;
            FHE.allow(playerDeck0, p.playerAddr);
            FHE.allowThis(playerDeck0);
            FHE.allow(playerDeck1, p.playerAddr);
            FHE.allowThis(playerDeck1);
        } else {
            if (allow0) {
                playerDeck0 = marketDeck[0].and(mask[0]);
                p.whotCardDeck[0] = playerDeck0;
                FHE.allow(playerDeck0, p.playerAddr);
                FHE.allowThis(playerDeck0);
            } else {
                playerDeck1 = marketDeck[1].and(mask[1]);
                p.whotCardDeck[1] = playerDeck1;
                FHE.allow(playerDeck1, p.playerAddr);
                FHE.allowThis(playerDeck1);
            }
        }
        $.players[currentIdx] = p;

        $.marketDeckMap = marketDeckMap;
    }

    function dealPendingPickN(GameData storage $, uint256 playerIdx, uint256 pickN) internal {
        $.players[playerIdx].pendingAction = PendingAction(pickN);
    }

    function dealGeneralMarket(
        GameData storage $,
        uint256 currentIdx,
        uint256 pickN,
        PlayerStoreMap playerStoreMap
    ) internal {
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        uint256 numCardsIn0 = 256 / marketDeckMap.getDeckCardSize();
        euint256[2] memory marketDeck = $.marketDeck;

        uint256[] memory activePlayers = playerStoreMap.getNonEmptyIdxs();

        for (uint256 i = 0; i < activePlayers.length; i++) {
            uint256 activeIdx = activePlayers[i];
            if (activeIdx != currentIdx) {
                PlayerData memory player = $.players[activeIdx];
                bool allow0;
                bool allowBothIdx;
                for (uint256 j = 0; j < pickN; j++) {
                    if (marketDeckMap.isMapNotEmpty()) {
                        uint256 cardIdx;
                        (marketDeckMap, player.deckMap, cardIdx) =
                            marketDeckMap.deal(player.deckMap);

                        assembly ("memory-safe") {
                            let allow := iszero(div(cardIdx, numCardsIn0))
                            allow0 := or(allow, allow0)
                            allowBothIdx := xor(allow, allow0)
                        }
                    }
                }
                uint256[2] memory mask = player.deckMap.computeMask();
                {
                    euint256 playerDeck0;
                    euint256 playerDeck1;
                    if (allowBothIdx) {
                        playerDeck0 = marketDeck[0].and(mask[0]);
                        playerDeck1 = marketDeck[1].and(mask[1]);
                        player.whotCardDeck[0] = playerDeck0;
                        player.whotCardDeck[1] = playerDeck1;
                        FHE.allow(playerDeck0, player.playerAddr);
                        FHE.allowThis(playerDeck0);
                        FHE.allow(playerDeck1, player.playerAddr);
                        FHE.allowThis(playerDeck1);
                    } else {
                        if (allow0) {
                            playerDeck0 = marketDeck[0].and(mask[0]);
                            player.whotCardDeck[0] = playerDeck0;
                            FHE.allow(playerDeck0, player.playerAddr);
                            FHE.allowThis(playerDeck0);
                        } else {
                            playerDeck1 = marketDeck[1].and(mask[1]);
                            player.whotCardDeck[1] = playerDeck1;
                            FHE.allow(playerDeck1, player.playerAddr);
                            FHE.allowThis(playerDeck1);
                        }
                    }
                }
                $.players[i] = player;
            }
        }

        $.marketDeckMap = marketDeckMap;
    }

    function dealPendingGeneralMarket(
        GameData storage $,
        uint256 currentIdx,
        uint256 pickN,
        PlayerStoreMap playerStoreMap
    ) internal {
        uint256[] memory activePlayers = playerStoreMap.getNonEmptyIdxs();
        for (uint256 i = 0; i < activePlayers.length; i++) {
            uint256 activeIdx = activePlayers[i];
            if (activeIdx != currentIdx) {
                $.players[activeIdx].pendingAction = PendingAction(pickN);
            }
        }
    }
}
