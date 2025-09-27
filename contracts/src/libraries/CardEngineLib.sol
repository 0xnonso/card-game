// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FHE, euint256, euint8} from "fhevm/lib/FHE.sol";

import {IRuleset} from "../interfaces/IRuleset.sol";

import {Card, CardLib} from "../types/Card.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";

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
    DeckMap deckMap;
    PendingAction pendingAction;
    uint16 score;
    euint256[2] hand;
}

struct GameData {
    address gameCreator;
    Card callCard;
    uint8 playerTurnIdx;
    GameStatus status;
    uint40 lastMoveTimestamp;
    // maxPlayers | playersLeftToJoin;
    uint8 packedJoinCapacity;
    uint8 initialHandSize;
    PlayerStoreMap playerStoreMap;
    uint8 numProposedPlayers;
    // card size
    IRuleset ruleSet;
    DeckMap marketDeckMap;
    euint256[2] marketDeck;
    PlayerData[] players;
    mapping(address => bool) isProposedPlayer;
    // Allows for easier retrieval of player's data index;
    mapping(address => uint256) playerIndex;
}

using CardEngineLib for GameData global;
using CardEngineLib for PlayerData global;

library CardEngineLib {
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

    function calculateAndSetPlayerScore(GameData storage $, uint256 playerIndex, uint256[2] memory marketDeck)
        internal
    {
        PlayerData memory player = $.players[playerIndex];
        DeckMap playerDeckMap = player.deckMap;
        uint256[] memory cardIndexes = playerDeckMap.getNonEmptyIdxs();

        DeckMap marketDeckMap = $.marketDeckMap;
        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardSize;
        uint16 total = 0;
        for (uint256 i = 0; i < cardIndexes.length; i++) {
            uint256 marketDeckIdx = cardIndexes[i];
            uint256 mask = (uint256(1) << cardSize) - 1;
            uint256 rawCard =
                marketDeck[marketDeckIdx / numCardsIn0] >> ((marketDeckIdx % numCardsIn0) * cardSize) & mask;
            Card card = CardLib.toCard(uint8(rawCard));
            (, uint256 cardValue) = $.ruleSet.getCardAttributes(card, cardSize);
            total += uint16(cardValue);
        }

        $.players[playerIndex].score = total;
    }

    function getCardToCommit(GameData storage $, PlayerData memory p, uint256 cardIdx) internal returns (euint8) {
        DeckMap marketDeckMap = $.marketDeckMap;
        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardSize;
        if (cardIdx > (numCardsIn0 - 1)) revert CardIndexOutOfBounds(cardIdx);
        if (marketDeckMap.isNotEmpty(cardIdx) || p.deckMap.isEmpty(cardIdx)) {
            revert CardIndexIsEmpty(cardIdx);
        }

        euint256 marketDeck = $.marketDeck[cardIdx / numCardsIn0];
        uint256 mask = (uint256(1) << cardSize) - 1;
        euint8 cardToCommit = marketDeck.shr(uint8((cardIdx % numCardsIn0) * cardSize)).and(mask).asEuint8();
        FHE.allowThis(cardToCommit);
        return cardToCommit;
    }

    function addPlayer(GameData storage $, address player, PlayerStoreMap playerStoreMap)
        internal
        returns (PlayerStoreMap)
    {
        PlayerData memory pData;
        pData.playerAddr = player;

        pData.deckMap = $.marketDeckMap.newMap();
        pData.hand[0] = FHE.asEuint256(0);
        pData.hand[1] = FHE.asEuint256(0);

        FHE.allow(pData.hand[0], player);
        FHE.allowThis(pData.hand[0]);
        FHE.allow(pData.hand[1], player);
        FHE.allowThis(pData.hand[1]);

        uint256 playerIndex = $.players.length;

        $.players.push(pData);
        $.playerIndex[pData.playerAddr] = playerIndex;

        return playerStoreMap.addPlayer(playerIndex);
    }

    function initializeMarketDeckMap(uint256 marketDeckLen, uint256 deckCardBitSize) internal pure returns (DeckMap) {
        uint56 cardSize = uint56(deckCardBitSize & 0x03);
        return DeckMap.wrap(uint56(((uint256(1) << marketDeckLen) - 1) << 2) | cardSize);
    }

    function emptyDeckMapAtIndex(PlayerData memory p, uint256 cardIdx) internal pure returns (DeckMap) {
        return p.deckMap.setToEmpty(cardIdx);
    }

    function dealInitialHand(
        GameData storage $,
        PlayerData memory p,
        uint256 index,
        DeckMap marketDeckMap,
        uint256 numPlayers,
        uint256 handSize
    ) internal returns (DeckMap) {
        uint256[] memory idxs = new uint256[](handSize);

        for (uint256 i = 0; i < idxs.length; i++) {
            idxs[i] = index + (i * numPlayers);
        }

        // DeckMap marketDeckMap = $.marketDeckMap;
        DeckMap playerDeckMap;
        (marketDeckMap, playerDeckMap) = marketDeckMap.deal(p.deckMap, idxs);
        $.players[index].deckMap = playerDeckMap;

        euint256[2] memory marketDeck = $.marketDeck;

        uint256[2] memory mask = playerDeckMap.computeMask();
        p.hand[0] = marketDeck[0].and(mask[0]);
        p.hand[1] = marketDeck[1].and(mask[1]);

        $.players[index].hand[0] = p.hand[0];
        FHE.allow(p.hand[0], p.playerAddr);
        FHE.allowThis(p.hand[0]);

        $.players[index].hand[1] = p.hand[1];
        FHE.allow(p.hand[1], p.playerAddr);
        FHE.allowThis(p.hand[1]);

        return marketDeckMap;
    }

    function deal(GameData storage $, PlayerData memory p, uint256 currentIdx, DeckMap marketDeckMap)
        internal
        returns (DeckMap)
    {
        // DeckMap marketDeckMap = $.marketDeckMap;
        uint256 numCardsIn0 = 256 / marketDeckMap.getDeckCardSize();

        if (marketDeckMap.isMapNotEmpty()) {
            uint256 cardIdx;

            (marketDeckMap, $.players[currentIdx].deckMap, cardIdx) = marketDeckMap.deal(p.deckMap);

            uint256 i = cardIdx / numCardsIn0;
            uint256 mask = p.deckMap.computeMask()[i];
            euint256 updatedcardDeck = $.marketDeck[i].and(mask);
            $.players[currentIdx].hand[i] = updatedcardDeck;
            FHE.allow(updatedcardDeck, p.playerAddr);
            FHE.allowThis(updatedcardDeck);
        }
        return marketDeckMap;
    }

    function dealPickN(GameData storage $, PlayerData memory p, uint256 currentIdx, DeckMap marketDeckMap, uint256 n)
        internal
        returns (DeckMap)
    {
        // DeckMap marketDeckMap = $.marketDeckMap;
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
            p.hand[0] = playerDeck0;
            p.hand[1] = playerDeck1;
            FHE.allow(playerDeck0, p.playerAddr);
            FHE.allowThis(playerDeck0);
            FHE.allow(playerDeck1, p.playerAddr);
            FHE.allowThis(playerDeck1);
        } else {
            if (allow0) {
                playerDeck0 = marketDeck[0].and(mask[0]);
                p.hand[0] = playerDeck0;
                FHE.allow(playerDeck0, p.playerAddr);
                FHE.allowThis(playerDeck0);
            } else {
                playerDeck1 = marketDeck[1].and(mask[1]);
                p.hand[1] = playerDeck1;
                FHE.allow(playerDeck1, p.playerAddr);
                FHE.allowThis(playerDeck1);
            }
        }
        $.players[currentIdx] = p;

        return marketDeckMap;
    }

    function dealPendingPickN(GameData storage $, uint256 playerIdx, uint256 pickN) internal {
        $.players[playerIdx].pendingAction = PendingAction(pickN);
    }

    function dealGeneralMarket(
        GameData storage $,
        uint256 currentIdx,
        uint256 pickN,
        DeckMap marketDeckMap,
        PlayerStoreMap playerStoreMap
    ) internal returns (DeckMap) {
        // DeckMap marketDeckMap = $.marketDeckMap;
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
                        (marketDeckMap, player.deckMap, cardIdx) = marketDeckMap.deal(player.deckMap);

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
                        player.hand[0] = playerDeck0;
                        player.hand[1] = playerDeck1;
                        FHE.allow(playerDeck0, player.playerAddr);
                        FHE.allowThis(playerDeck0);
                        FHE.allow(playerDeck1, player.playerAddr);
                        FHE.allowThis(playerDeck1);
                    } else {
                        if (allow0) {
                            playerDeck0 = marketDeck[0].and(mask[0]);
                            player.hand[0] = playerDeck0;
                            FHE.allow(playerDeck0, player.playerAddr);
                            FHE.allowThis(playerDeck0);
                        } else {
                            playerDeck1 = marketDeck[1].and(mask[1]);
                            player.hand[1] = playerDeck1;
                            FHE.allow(playerDeck1, player.playerAddr);
                            FHE.allowThis(playerDeck1);
                        }
                    }
                }
                $.players[i] = player;
            }
        }

        // $.marketDeckMap = marketDeckMap;
        return marketDeckMap;
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
