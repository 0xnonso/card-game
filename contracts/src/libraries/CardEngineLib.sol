// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRuleset} from "../interfaces/IRuleset.sol";
import {Card, CardLib} from "../types/Card.sol";
import {HookPermissions} from "../types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "../types/Map.sol";
import {FHE, ebool, euint16, euint256, euint8} from "@fhevm/solidity/lib/FHE.sol";

enum Action {
    Play,
    Defend,
    Draw,
    Neutral
}

enum GameStatus {
    None,
    Started,
    Ended
}

struct PlayerData {
    address playerAddr;
    DeckMap deckMap;
    uint8 pendingAction;
    bool forfeited;
    euint256[2] hand;
}

struct PlayerScoreData {
    address playerAddr;
    DeckMap deckMap;
    Card[] hand;
}

struct GameData {
    address gameCreator;
    Card callCard;
    uint8 playerTurnIdx;
    GameStatus status;
    uint40 lastMoveTimestamp;
    uint8 numProposedPlayers;
    HookPermissions hookPermissions;
    PlayerStoreMap playerStoreMap;
    IRuleset ruleset;
    DeckMap marketDeckMap; // a.k.a discard-pile map
    uint8 initialHandSize;
    uint8 playersLeftToJoin;
    bool recycleMarketDeck;
    euint256[2] marketDeck;
    PlayerData[] players;
    euint8 randomEncryptedIndex;
    mapping(address => bool) isProposedPlayer;
    // Allows for easier retrieval of player's data index;
    mapping(address => uint256) playerIndex;
}

using CardEngineLib for GameData global;
using CardEngineLib for PlayerData global;

library CardEngineLib {
    using FHE for *;

    error CardIndexIsEmpty(uint256);

    uint8 constant MAX_DEAL_N = 16;
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

    function getPlayerHand(DeckMap playerDeckMap, DeckMap marketDeckMap, uint256[2] memory marketDeck) internal view returns (Card[] memory) {
        uint256[] memory cardIndexes = playerDeckMap.getNonEmptyIdxs();
        Card[] memory playerHand = new Card[](cardIndexes.length);

        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardSize;
        uint256 mask = _cardMask(cardSize);
        for (uint256 i = 0; i < cardIndexes.length; i++) {
            uint256 marketDeckIdx = cardIndexes[i];
            uint256 rawCard =
                (marketDeck[marketDeckIdx / numCardsIn0] >> ((marketDeckIdx % numCardsIn0) * cardSize)) & mask;
            playerHand[i] = CardLib.toCard(uint8(rawCard));
        }
        return playerHand;
    }

    function grantAccessToHand(euint256[2] memory hand, address grantee) internal {
        FHE.allowTransient(hand[0], grantee);
        FHE.allowTransient(hand[1], grantee);
    }

    function getCardToCommit(GameData storage $, DeckMap playerDeckMap, uint256 cardIdx) internal returns (euint8) {
        DeckMap marketDeckMap = $.marketDeckMap;
        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint256 numCardsIn0 = 256 / cardSize;

        if (marketDeckMap.isNotEmpty(cardIdx) || playerDeckMap.isEmpty(cardIdx)) {
            revert CardIndexIsEmpty(cardIdx);
        }

        euint256 marketDeck = $.marketDeck[cardIdx / numCardsIn0];
        euint8 cardToCommit =
            marketDeck.shr(uint8((cardIdx % numCardsIn0) * cardSize)).and(_cardMask(cardSize)).asEuint8();
        FHE.allowThis(cardToCommit);

        if ($.recycleMarketDeck) {
            euint256 encNonEmptyIdxsPacked;
            uint256 nonEmptyIdxsPacked;
            uint256[] memory nonEmptyIdxs = marketDeckMap.getNonEmptyIdxs(42);
            for (uint256 i = 0; i < nonEmptyIdxs.length; i++) {
                nonEmptyIdxsPacked |= (nonEmptyIdxs[i] << (i * 6));
            }
            // generate random index from at most the first 42 market deck indexes
            encNonEmptyIdxsPacked = FHE.asEuint256(nonEmptyIdxsPacked);
            euint8 randIndex = FHE.asEuint8(
                FHE.shr(FHE.mul(FHE.asEuint32(FHE.randEuint16()), FHE.asEuint32(uint32(nonEmptyIdxs.length))), 16)
            );
            euint8 encIndex = FHE.asEuint8(encNonEmptyIdxsPacked.shr(randIndex.mul(6)).and(0x3f));
            $.randomEncryptedIndex = encIndex;

            FHE.allowThis(encIndex);
        }
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

        _fheAllow(pData.hand[0], player);
        _fheAllow(pData.hand[1], player);

        uint256 playerIndex = $.players.length;

        $.players.push(pData);
        $.playerIndex[pData.playerAddr] = playerIndex;

        return playerStoreMap.addPlayer(playerIndex);
    }

    function initializeMarketDeckMap(uint256 marketDeckLen, uint256 deckCardBitSize) internal pure returns (DeckMap) {
        uint64 cardSize = uint64(deckCardBitSize & 0x03);
        return DeckMap.wrap(uint64(((uint256(1) << marketDeckLen) - 1) << 2) | cardSize);
    }

    function updatePlayerHand(
        GameData storage $,
        PlayerData memory p,
        uint256 playerIdx,
        euint8 encryptedCard,
        uint256 cardIdx
    ) internal returns (DeckMap updatedPlayerDeckMap, euint256[2] memory updatedPlayerHand) {
        updatedPlayerDeckMap = p.deckMap.setToEmpty(cardIdx);
        p.deckMap = updatedPlayerDeckMap;

        uint256 numCardsIn0 = 256 / updatedPlayerDeckMap.getDeckCardSize();
        uint256 i = cardIdx / numCardsIn0;
        uint256 mask = updatedPlayerDeckMap.computeMask()[i];
        euint256 updatedDeck = $.marketDeck[i].and(mask);
        p.hand[i] = updatedDeck;
        updatedPlayerHand = p.hand;
        $.players[playerIdx] = p;
        _fheAllow(updatedDeck, p.playerAddr);

        if ($.recycleMarketDeck) {
            replenishMarketDeck($, encryptedCard, cardIdx);
            $.marketDeckMap.fill(cardIdx);
        }
    }

    function _swapFrom(
        euint256[2] memory marketDeck,
        euint8 encryptedCard,
        euint8 indexToSwapFrom,
        uint256 cardMask,
        euint8[2] memory newCardIndexValue,
        uint8 index
    ) internal returns (euint256) {
        euint256 mask = FHE.asEuint256(cardMask).shl(indexToSwapFrom).not();
        newCardIndexValue[index] = marketDeck[index].shr(indexToSwapFrom).and(cardMask).asEuint8();
        return marketDeck[index].and(mask).or(encryptedCard.asEuint256().shl(indexToSwapFrom));
    }

    function replenishMarketDeck(GameData storage $, euint8 encryptedCard, uint256 cardIndex) internal {
        euint256[2] memory marketDeck = $.marketDeck;
        DeckMap marketDeckMap = $.marketDeckMap;
        euint8 encIndex = $.randomEncryptedIndex;

        uint256 cardSize = marketDeckMap.getDeckCardSize();
        uint8 numCardsIn0 = uint8(256 / cardSize);
        ebool[2] memory fromMDeck;
        fromMDeck[0] = encIndex.lt(numCardsIn0);
        fromMDeck[1] = encIndex.ge(numCardsIn0);

        euint8[2] memory newCardIndexValue;
        newCardIndexValue[0] = FHE.asEuint8(0);
        newCardIndexValue[1] = FHE.asEuint8(0);

        uint256 cardMask = _cardMask(cardSize);
        marketDeck[0] = FHE.select(
            fromMDeck[0],
            _swapFrom(marketDeck, encryptedCard, encIndex.mul(uint8(cardSize)), cardMask, newCardIndexValue, 0), // marketDeck[0].shr(swapFromIndex).and((uint256(1) << marketDeckMap.getDeckCardSize()) - 1)
            marketDeck[0]
        );
        marketDeck[1] = FHE.select(
            fromMDeck[1],
            _swapFrom(
                marketDeck,
                encryptedCard,
                encIndex.sub(numCardsIn0).mul(uint8(cardSize)),
                cardMask,
                newCardIndexValue,
                1
            ),
            marketDeck[1]
        );

        uint256 indexToSwapTo = (cardIndex % numCardsIn0) * cardSize;
        uint256 mask = ~(cardMask << indexToSwapTo);
        uint256 i = cardIndex / numCardsIn0;
        marketDeck[i] = marketDeck[i].and(mask).or(
            FHE.select(fromMDeck[0], newCardIndexValue[0], newCardIndexValue[1]).asEuint256().shl(uint8(indexToSwapTo))
        );

        $.marketDeck[0] = marketDeck[0];
        $.marketDeck[1] = marketDeck[1];

        FHE.allowThis(marketDeck[0]);
        FHE.makePubliclyDecryptable(marketDeck[0]);
        FHE.allowThis(marketDeck[1]);
        FHE.makePubliclyDecryptable(marketDeck[1]);
    }

    function dealInitialHand(
        GameData storage $,
        uint256 index,
        DeckMap marketDeckMap,
        uint256 numPlayers,
        uint256 handSize
    ) internal returns (DeckMap) {
        PlayerData memory p = $.players[index];
        uint256[] memory idxs = new uint256[](handSize);

        for (uint256 i = 0; i < idxs.length; i++) {
            idxs[i] = index + (i * numPlayers);
        }

        DeckMap playerDeckMap;
        (marketDeckMap, playerDeckMap) = marketDeckMap.deal(p.deckMap, idxs);
        p.deckMap = playerDeckMap;

        euint256[2] memory marketDeck = $.marketDeck;

        uint256[2] memory mask = playerDeckMap.computeMask();
        p.hand[0] = marketDeck[0].and(mask[0]);
        p.hand[1] = marketDeck[1].and(mask[1]);

        _fheAllow(p.hand[0], p.playerAddr);
        _fheAllow(p.hand[1], p.playerAddr);

        $.players[index] = p;

        return marketDeckMap;
    }

    function deal(GameData storage $, uint256 currentIdx, DeckMap marketDeckMap) internal returns (DeckMap) {
        PlayerData memory p = $.players[currentIdx];
        uint256 numCardsIn0 = 256 / marketDeckMap.getDeckCardSize();

        if (marketDeckMap.isMapNotEmpty()) {
            uint256 cardIdx;

            (marketDeckMap, p.deckMap, cardIdx) = marketDeckMap.deal(p.deckMap);
            $.players[currentIdx].deckMap = p.deckMap;
            uint256 i = cardIdx / numCardsIn0;
            uint256 mask = p.deckMap.computeMask()[i];
            euint256 updatedDeck = $.marketDeck[i].and(mask);
            $.players[currentIdx].hand[i] = updatedDeck;
            _fheAllow(updatedDeck, p.playerAddr);
        }
        return marketDeckMap;
    }

    function dealN(GameData storage $, uint256 currentIdx, DeckMap marketDeckMap, uint256 n)
        internal
        returns (DeckMap)
    {
        PlayerData memory p = $.players[currentIdx];
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
            _fheAllow(playerDeck0, p.playerAddr);
            _fheAllow(playerDeck1, p.playerAddr);
        } else {
            if (allow0) {
                playerDeck0 = marketDeck[0].and(mask[0]);
                p.hand[0] = playerDeck0;
                _fheAllow(playerDeck0, p.playerAddr);
            } else {
                playerDeck1 = marketDeck[1].and(mask[1]);
                p.hand[1] = playerDeck1;
                _fheAllow(playerDeck1, p.playerAddr);
            }
        }
        $.players[currentIdx] = p;

        return marketDeckMap;
    }

    function dealPendingN(GameData storage $, uint256 playerIdx, uint256 n) internal {
        uint8 pendingDeal = $.players[playerIdx].pendingAction;
        uint8 newPendingDeal = pendingDeal + uint8(n);
        if (newPendingDeal > MAX_DEAL_N) {
            newPendingDeal = MAX_DEAL_N;
        }
        $.players[playerIdx].pendingAction = newPendingDeal;
    }

    function dealGeneralMarket(
        GameData storage $,
        uint256 currentIdx,
        uint256 n,
        DeckMap marketDeckMap,
        PlayerStoreMap playerStoreMap
    ) internal returns (DeckMap) {
        uint256 numCardsIn0 = 256 / marketDeckMap.getDeckCardSize();
        euint256[2] memory marketDeck = $.marketDeck;

        uint256[] memory activePlayers = playerStoreMap.getNonEmptyIdxs();

        for (uint256 i = 0; i < activePlayers.length; i++) {
            uint256 activeIdx = activePlayers[i];
            if (activeIdx != currentIdx) {
                PlayerData memory player = $.players[activeIdx];
                bool allow0;
                bool allowBothIdx;
                for (uint256 j = 0; j < n; j++) {
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
                        _fheAllow(playerDeck0, player.playerAddr);
                        _fheAllow(playerDeck1, player.playerAddr);
                    } else {
                        if (allow0) {
                            playerDeck0 = marketDeck[0].and(mask[0]);
                            player.hand[0] = playerDeck0;
                            _fheAllow(playerDeck0, player.playerAddr);
                        } else {
                            playerDeck1 = marketDeck[1].and(mask[1]);
                            player.hand[1] = playerDeck1;
                            _fheAllow(playerDeck1, player.playerAddr);
                        }
                    }
                }
                $.players[i] = player;
            }
        }
        return marketDeckMap;
    }

    function dealPendingGeneralMarket(GameData storage $, uint256 currentIdx, uint256 n, PlayerStoreMap playerStoreMap)
        internal
    {
        uint256[] memory activePlayers = playerStoreMap.getNonEmptyIdxs();
        for (uint256 i = 0; i < activePlayers.length; i++) {
            uint256 activeIdx = activePlayers[i];
            if (activeIdx != currentIdx) {
                dealPendingN($, activeIdx, n);
            }
        }
    }

    function resolvePending(
        GameData storage $,
        uint256 currentIdx,
        DeckMap marketDeckMap,
        DeckMap playerDeckMap,
        uint8 pendingAction
    ) internal returns (DeckMap, DeckMap) {
        PlayerData storage p = $.players[currentIdx];
        if (pendingAction > 0) {
            for (uint8 i = 0; i < pendingAction; i++) {
                if (marketDeckMap.isMapNotEmpty()) {
                    (marketDeckMap, playerDeckMap,) = marketDeckMap.deal(playerDeckMap);
                }
            }
            p.pendingAction = 0;
            p.deckMap = playerDeckMap;
        }
        return (marketDeckMap, playerDeckMap);
    }

    function _cardMask(uint256 cardSize) internal pure returns (uint256) {
        return (uint256(1) << cardSize) - 1;
    }

    function _fheAllow(euint256 value, address grantee) internal {
        FHE.allow(value, grantee);
        FHE.allowThis(value);
    }
}
