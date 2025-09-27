// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AsyncHandler} from "./base/AsyncHandler.sol";
import {CachePositionBase} from "./base/CachePositionBase.sol";
import {EInputData, EInputHandler} from "./base/EInputHandler.sol";
import {ADDRESS_MASK, U16_MASK, U64_MASK, U8_MASK} from "./helpers/Constants.sol";
import {ICardEngine} from "./interfaces/ICardEngine.sol";
import {IManagerHook, IManagerView} from "./interfaces/IManager.sol";
import {IRuleset} from "./interfaces/IRuleset.sol";
import {Action, CardEngineLib, GameData, GameStatus, PendingAction, PlayerData} from "./libraries/CardEngineLib.sol";
import {ConditionalsLib} from "./libraries/ConditionalsLib.sol";
import {CacheManager, CacheValue} from "./types/Cache.sol";
import {Card, CardLib} from "./types/Card.sol";
import {DeckMap, PlayerStoreMap} from "./types/Map.sol";
import {FHE, euint256, euint8} from "fhevm/lib/FHE.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

contract CardEngine is ICardEngine, CachePositionBase, AsyncHandler, EInputHandler, ReentrancyGuard {
    using FHE for *;
    using ConditionalsLib for *;

    uint256 constant MAX_DELAY = 4 minutes;
    // Max number of players in a game.
    uint256 constant MAX_PLAYERS_LEN = 8;
    uint256 constant MIN_PLAYERS_LEN = 2;

    // game ID
    uint256 internal cardGameId = 1;

    // Game Data.
    mapping(uint256 gameId => GameData) internal cardGame;

    /// ERRORS
    error PlayerAlreadyInGame();
    error GameAlreadyStarted();
    error GameNotStarted();
    error NotPlayerTurn();
    error ResolvePendingAction();
    error NoPendingAction();
    error NotProposedPlayer(address player);
    error CannotStartGame();
    error PlayersLimitExceeded();
    error PlayersLimitNotMet();
    error CannotBootOutPlayer(address player);
    error InvalidGameAction(Action action);
    error PlayerAlreadyCommittedAction();
    error InvalidPlayerIndex();
    error InvalidProposedPlayer();
    error CardSizeNotSupported();
    error CallFailed();

    /// EVENTS
    event PlayerForfeited(uint256 indexed gameId, uint256 playerIndex);
    event PlayerJoined(uint256 indexed gameId, address player);
    event MoveExecuted(uint256 indexed gameId, uint256 pTurnIndex, Action action);
    event PendingActionFulfilled(uint256 indexed gameId, uint256 playerIndex, PendingAction action);
    event GameCreated(uint256 indexed gameId, address gameCreator);
    event GameStarted(uint256 indexed gameId);
    event GameEnded(uint256 indexed gameId);

    constructor() AsyncHandler() {}

    function createGame(
        EInputData calldata inputData,
        bytes calldata inputProof,
        address[] calldata proposedPlayers,
        IRuleset gameRuleset,
        uint256 cardBitSize,
        uint256 cardDeckSize,
        uint8 maxPlayers,
        uint8 initialHandSize,
        bool enableManager
    ) public returns (uint256 gameId) {
        gameId = cardGameId;
        GameData storage game = cardGame[gameId];

        // if proposed players is set, then max players is the length of proposed players.
        // if proposed players is not set, then max players is the max players passed in.
        uint8 numProposedPlayers = uint8(proposedPlayers.length);
        maxPlayers = numProposedPlayers != 0 ? numProposedPlayers : maxPlayers;

        if (maxPlayers > MAX_PLAYERS_LEN) revert PlayersLimitExceeded();
        if (maxPlayers < MIN_PLAYERS_LEN) revert PlayersLimitNotMet();

        for (uint256 i = 0; i < numProposedPlayers; i++) {
            if (msg.sender == proposedPlayers[i]) revert InvalidProposedPlayer();
            game.isProposedPlayer[proposedPlayers[i]] = true;
        }

        {
            (CacheValue g, uint256 slot) = loadCache(game, 1);

            // set game ruleset and validate card size.
            g = storeRuleset(g, gameRuleset);
            if (!gameRuleset.supportsCardSize(cardBitSize)) revert CardSizeNotSupported();
            // initialize market deck map with card size and deck size.
            g = storeMarketDeckMap(g, CardEngineLib.initializeMarketDeckMap(cardDeckSize, cardBitSize));
            g.toStorage(slot);

            (g, slot) = loadCache(game, 0);

            g = storeMaxPlayers(g, maxPlayers); // set max players.
            g = storeNumProposedPlayers(g, numProposedPlayers);
            g = storePlayersLeftToJoin(g, maxPlayers); // initially, players left to join is max players.
            // `gameCreator` is the msg.sender if `enableManager` is true, otherwise it's address(0).
            g = storeGameCreator(g, enableManager ? msg.sender : address(0));
            g = storeHandSize(g, initialHandSize); // set initial hand size.
            g.toStorage(slot);
        }

        // initialize market deck.
        euint256[2] memory marketDeck = _handleInputData(inputData, inputProof);
        game.marketDeck[0] = marketDeck[0];
        game.marketDeck[1] = marketDeck[1];
        FHE.allowThis(marketDeck[0]);
        FHE.allowThis(marketDeck[1]);

        unchecked {
            cardGameId++;
        }

        emit GameCreated(gameId, msg.sender);
    }

    function joinGame(uint256 gameId) public nonReentrant {
        GameData storage game = cardGame[gameId];
        (CacheValue g, uint256 slot) = loadCache(game, 0);

        if (loadStatus(g).notEqs(GameStatus.None)) revert GameAlreadyStarted();

        address playerToAdd = msg.sender;
        PlayerStoreMap playerStoreMap = loadPlayerStoreMap(g);
        uint8 playersLeftToJoin = loadPlayersLeftToJoin(g);
        address gameCreator = loadGameCreator(g);

        // use player store map to check if player is already in game.
        if (game.isPlayerActive(playerToAdd, playerStoreMap)) revert PlayerAlreadyInGame();
        if (playerToAdd == gameCreator) revert InvalidProposedPlayer();

        // if player is not a proposed player and `proposed players` is not set, then check if max players limit has been reached.
        // if proposed players is set (i.e proposed players array > 0), then check if player is in the proposed players list.
        bool isProposedPlayer =
            loadNumProposedPlayers(g) != 0 ? game.isProposedPlayer[playerToAdd] : playersLeftToJoin != 0;

        if (isProposedPlayer) {
            playerStoreMap = game.addPlayer(playerToAdd, playerStoreMap);
            playersLeftToJoin--;
            g = storePlayersLeftToJoin(g, playersLeftToJoin);
            g = storePlayerStoreMap(g, playerStoreMap);
            g.toStorage(slot);
        } else {
            revert NotProposedPlayer(playerToAdd);
        }

        // if game creator is set, call `onJoinGame` hook.
        // address gameCreator = loadGameCreator(g);
        // IManagerHook(gameCreator).onJoinGame(loadHookPermission(g0), gameId, playerToAdd);
        if (gameCreator != address(0)) {
            IManagerHook(gameCreator).onJoinGame(gameId, playerToAdd);
        }

        emit PlayerJoined(gameId, playerToAdd);
    }

    function startGame(uint256 gameId) external {
        GameData storage game = cardGame[gameId];
        PlayerData[] memory players = game.players;

        CacheValue g0;
        (CacheValue g1, uint256 slot1) = loadCache(game, 1);

        address gameCreator;
        uint256 joined;
        {
            uint256 slot0;
            (g0, slot0) = loadCache(game, 0);

            uint256 playersLeftToJoin = loadPlayersLeftToJoin(g0);
            gameCreator = loadGameCreator(g0);
            joined = loadMaxPlayers(g0) - playersLeftToJoin;

            // can only start game if:
            //  - `playersLeftToJoin` is zero (i.e all players have joined).
            //  - game creator is the caller and at least 2 players have joined.
            bool canStartGame;
            assembly ("memory-safe") {
                // forgefmt: disable-next-item
                canStartGame := or(iszero(playersLeftToJoin), and(eq(caller(), gameCreator), gt(joined, 0x01)))
            }

            // if game can start, all players are dealt an initial hand, and each player's score is set to the minimum value of 65,535.
            if (!canStartGame) {
                revert CannotStartGame();
            }

            g0 = storeStatus(g0, GameStatus.Started);
            // set player turn index to the computed start index by the ruleset.
            g0 = storePlayerTurnIndex(g0, loadRuleset(g1).computeStartIndex(loadPlayerStoreMap(g0)));
            g0.toStorage(slot0);
        }

        DeckMap marketDeckMap = loadMarketDeckMap(g1);
        uint8 handSize = loadHandSize(g0);
        for (uint256 i = 0; i < players.length; i++) {
            game.setPlayerScoreToMin(i);
            marketDeckMap = game.dealInitialHand(players[i], i, marketDeckMap, joined, handSize);
        }
        // game.marketDeckMap = marketDeckMap;
        g1 = storeMarketDeckMap(g1, marketDeckMap);
        g1.toStorage(slot1);

        emit GameStarted(gameId);

        // if game creator is set, call `onStartGame` hook.
        // at this point, the game might end immediately if the call to the hook returns true.
        // this is to allow the game manager to force end a game if needed (i.e if the game does not require any moves to be played).
        if (gameCreator != address(0)) {
            bool end = IManagerHook(gameCreator).onStartGame(gameId);
            // `currentPlayerIdx` is set to 0. it does not matter what is passed here since the current player is not relevant here.
            // `playerStoreMap` is set to 0 to trigger the game end condition in `finish`.
            if (end) finish(gameId, game, 0, PlayerStoreMap.wrap(0), loadMarketDeckMap(g1));
        }
    }

    function commitMove(uint256 gameId, Action action, uint256 cardIndex, bytes memory extraData) external {
        ensureNoCommittedAction(gameId);

        GameData storage game = cardGame[gameId];
        (CacheValue g,) = loadCache(game, 0);

        ensureGameStarted(loadStatus(g));

        uint256 currentTurnIndex = loadPlayerTurnIndex(g);
        PlayerData storage playerSlot = game.players[currentTurnIndex];
        PlayerData memory player;
        // store only player address and deckMap.
        assembly ("memory-safe") {
            let value := sload(playerSlot.slot)
            mstore(player, and(value, ADDRESS_MASK))
            mstore(add(player, 0x20), and(shr(160, value), U64_MASK))
        }

        ensurePlayerTurn(player.playerAddr);

        if (!action.eqsOr(Action.Play, Action.Defend)) {
            revert InvalidGameAction(action);
        }

        // get card to commit and updated player deck map.
        euint8 cardToCommit = game.getCardToCommit(player, cardIndex);
        DeckMap updatedPlayerDeckMap = player.emptyDeckMapAtIndex(cardIndex);

        _commitMove(gameId, cardToCommit, action, updatedPlayerDeckMap, currentTurnIndex, extraData);
    }

    function executeMove(uint256 gameId, Action action) external nonReentrant {
        GameData storage game = cardGame[gameId];
        (CacheValue g0, uint256 slot0) = loadCache(game, 0);
        (CacheValue g1, uint256 slot1) = loadCache(game, 1);

        ensureGameStarted(loadStatus(g0));

        uint8 playerTurnIdx = loadPlayerTurnIndex(g0);
        address playerAddr = game.players[playerTurnIdx].playerAddr;

        ensurePlayerTurn(playerAddr);
        ensureNoCommittedAction(gameId);

        if (!action.eqsOr(Action.GoToMarket, Action.Pick)) {
            revert InvalidGameAction(action);
        }

        // if action is GoToMarket, player must not have a pending action.
        // if action is Pick, player must have a pending action.
        (g0, g1) = goToMarketOrPick(gameId, game, action, playerTurnIdx, g0, g1);
        g0.toStorage(slot0);
        g1.toStorage(slot1);

        // if game creator is set, call `onExecuteMove` hook with an empty card since no card is played.
        address gameCreator = loadGameCreator(g0);
        // Card(0xff) represents an invaild or empty card.
        if (gameCreator != address(0)) {
            IManagerHook(gameCreator).onExecuteMove(gameId, playerAddr, CardLib.toCard(0xff), action);
        }
        // finally, check if game can end.
        finish(gameId, game, playerTurnIdx, loadPlayerStoreMap(g0), loadMarketDeckMap(g1));
    }

    function forfeit(uint256 gameId) external {
        GameData storage game = cardGame[gameId];

        (CacheValue g0, uint256 slot0) = loadCache(game, 0);
        (CacheValue g1,) = loadCache(game, 1);

        ensureGameStarted(loadStatus(g0));

        uint256 playerIdx = game.getPlayerIndex(msg.sender);
        g0 = _forfeit(gameId, playerIdx, loadRuleset(g1), g0);
        g0.toStorage(slot0);
        finish(gameId, game, playerIdx, loadPlayerStoreMap(g0), loadMarketDeckMap(g1));
    }

    function bootOut(uint256 gameId) external {
        GameData storage game = cardGame[gameId];
        (CacheValue g0, uint256 slot0) = loadCache(game, 0);

        ensureGameStarted(loadStatus(g0));

        uint256 turnIdx = loadPlayerTurnIndex(g0);
        uint40 lastMoveTimestamp = loadLastMoveTimestamp(g0);
        address player = game.players[turnIdx].playerAddr;

        bool canBootOut = (lastMoveTimestamp + MAX_DELAY) <= block.timestamp;

        // if game creator is set, call `canBootOut` hook to check if player can be booted out.
        // this overrides the default boot out condition of `lastMoveTimestamp + MAX_DELAY <= block.timestamp`.
        address gameCreator = loadGameCreator(g0);
        if (gameCreator != address(0)) {
            bytes memory payload =
                abi.encodeWithSelector(IManagerView.canBootOut.selector, gameId, player, lastMoveTimestamp);
            (bool success, bytes memory returnData) = gameCreator.call(payload);
            if (!success) revert CallFailed();
            canBootOut = abi.decode(returnData, (bool));
        }

        if (!canBootOut) revert CannotBootOutPlayer(player);

        (CacheValue g1,) = loadCache(game, 1);

        g0 = _forfeit(gameId, turnIdx, loadRuleset(g1), g0);
        g0.toStorage(slot0);
        finish(gameId, game, turnIdx, loadPlayerStoreMap(g0), loadMarketDeckMap(g1));
    }

    function handleCommitMove(uint256 requestId, uint8 rawCard, bytes[] memory signatures) external virtual override {
        CommittedCard memory cc = getCommittedMove(requestId);
        // validate callback signature and that this is the latest request.
        __validateCallbackSignature(requestId, cc.gameId, signatures);
        GameData storage game = cardGame[cc.gameId];
        Card card = CardLib.toCard(rawCard);
        game.players[cc.playerIndex].deckMap = cc.updatedPlayerDeckMap;

        (CacheValue g0, uint256 slot0) = loadCache(game, 0);
        (CacheValue g1, uint256 slot1) = loadCache(game, 1);

        address gameCreator = loadGameCreator(g0);

        // execute the move.
        (g0, g1) = playOrDefend(cc.gameId, game, cc.action, card, gameCreator, g0, g1, cc.extraData);
        g0.toStorage(slot0);
        g1.toStorage(slot1);

        // if game creator is set, call `onExecuteMove` hook.
        if (gameCreator != address(0)) {
            bytes memory payload = abi.encodeWithSelector(
                IManagerHook.onExecuteMove.selector, cc.gameId, game.players[cc.playerIndex].playerAddr, card, cc.action
            );
            (bool success,) = gameCreator.call(payload);
            if (!success) revert CallFailed();
        }
        // clean up commitment and check if game can end.
        clearCommitment(cc.gameId, requestId);
        finish(cc.gameId, game, cc.playerIndex, loadPlayerStoreMap(g0), loadMarketDeckMap(g1));
    }

    function handleCommitMarketDeck(uint256 requestId, uint256[2] memory marketDeck, bytes[] memory signatures)
        external
        virtual
        override
        nonReentrant
    {
        CommittedMarketDeck memory cmd = getCommittedMarketDeck(requestId);
        // validate callback signature and that this is the latest request.
        __validateCallbackSignature(requestId, cmd.gameId, signatures);
        GameData storage game = cardGame[cmd.gameId];
        PlayerData[] storage players = game.players;
        // get only active players.
        PlayerStoreMap playerStoreMap = game.playerStoreMap;
        uint256[] memory playerIndexes = playerStoreMap.getNonEmptyIdxs();

        for (uint256 i = 0; i < playerIndexes.length; i++) {
            game.calculateAndSetPlayerScore(playerIndexes[i], marketDeck);
        }

        // if game creator is set, call `onFinishGame` hook with players score data.
        // players score data is computed as packed [score, address] value for each player in the game.
        address gameCreator = game.gameCreator;
        if (gameCreator != address(0)) {
            uint256[] memory playersScoreData = new uint256[](players.length);
            for (uint256 i = 0; i < playersScoreData.length; i++) {
                PlayerData storage player = players[i];
                assembly ("memory-safe") {
                    let playerSlot := player.slot
                    let slotValue := sload(playerSlot)
                    let score := and(shr(232, slotValue), U16_MASK)
                    let playerAddr := and(slotValue, ADDRESS_MASK)
                    mstore(add(add(playersScoreData, 0x20), mul(i, 0x20)), or(shl(160, score), playerAddr))
                    // get [score, address] value and set `playersScoreData[i] = value`
                }
            }

            bytes memory payload =
                abi.encodeWithSelector(IManagerHook.onFinishGame.selector, cmd.gameId, playersScoreData);
            (bool success,) = gameCreator.call(payload);
            if (!success) revert CallFailed();
        }
    }

    /// Fails silently. Might be an anti patern? Todo(nonso): fix?
    function finish(
        uint256 gameId,
        GameData storage game,
        uint256 currentPlayerIdx,
        PlayerStoreMap playerStoreMap,
        DeckMap marketDeckMap
    ) internal {
        PlayerData memory player = game.players[currentPlayerIdx];

        bool playerStoreEmpty = playerStoreMap.isMapEmpty() || playerStoreMap.len() == 1;
        bool gameMarketDeckEmpty = marketDeckMap.isMapEmpty();
        bool playerDeckEmpty = player.deckMap.isMapEmpty();

        // game can end if:
        //  - game market deck is empty.
        //  - player deck is empty.
        //  - no player or only one player is active.
        bool shouldEnd;
        assembly ("memory-safe") {
            shouldEnd := or(or(gameMarketDeckEmpty, playerDeckEmpty), playerStoreEmpty)
        }

        if (shouldEnd) {
            ensureNoCommittedAction(gameId);
            _commitMarketDeck(gameId, game.marketDeck);
            game.status = GameStatus.Ended;

            emit GameEnded(gameId);
        }
    }

    function _forfeit(uint256 gameId, uint256 playerIdx, IRuleset ruleset, CacheValue g0)
        internal
        returns (CacheValue)
    {
        g0 = storePlayerStoreMap(g0, loadPlayerStoreMap(g0).removePlayer(playerIdx));
        // if the forfeiting player is the current player, update the turn index to the next player.
        if (loadPlayerTurnIndex(g0) == playerIdx) {
            g0 = storePlayerTurnIndex(g0, ruleset.computeNextTurnIndex(loadPlayerStoreMap(g0), playerIdx));
        }

        emit PlayerForfeited(gameId, playerIdx);
        return g0;
    }

    function playOrDefend(
        uint256 gameId,
        GameData storage game,
        Action action,
        Card card,
        address gameCreator,
        CacheValue g0,
        CacheValue g1,
        bytes memory extraData
    ) internal returns (CacheValue, CacheValue) {
        PlayerData memory player;
        IRuleset.ResolveMoveParams memory moveParams;

        {
            uint8 currentIdx = loadPlayerTurnIndex(g0);
            player = game.players[currentIdx];
            PendingAction pendingAction = player.pendingAction;

            // clear pending action if any.
            if (pendingAction.notEqs(PendingAction.None)) {
                game.players[currentIdx].pendingAction = PendingAction.None;
            }

            moveParams.gameAction = action;
            moveParams.pendingAction = pendingAction;
            moveParams.card = card;
            moveParams.callCard = loadCallCard(g0);
            moveParams.currentPlayerIndex = currentIdx;
            moveParams.extraData = extraData;
            moveParams.playerStoreMap = loadPlayerStoreMap(g0);
        }

        IRuleset ruleset = loadRuleset(g1);
        // address gameCreator = loadGameCreator(g0);
        // check if player is eligible for a special move. this is only possible if the game has a manager.
        bool isEligibleForSpecialMove = gameCreator != address(0) && ruleset.isSpecialMoveCard(moveParams.card)
            ? IManagerView(gameCreator).hasSpecialMoves(gameId, player.playerAddr, moveParams.card, moveParams.gameAction)
            : false;

        moveParams.isSpecial = isEligibleForSpecialMove;
        DeckMap marketDeckMap = loadMarketDeckMap(g1);
        moveParams.cardSize = marketDeckMap.getDeckCardSize();

        {
            // resolve move and get effect.
            IRuleset.Effect memory effect = ruleset.resolveMove(moveParams);

            marketDeckMap = _applyEffect(game, effect, moveParams.playerStoreMap, marketDeckMap);
            g1 = storeMarketDeckMap(g1, marketDeckMap);
            // update player turn index here.
            g0 = storePlayerTurnIndex(g0, effect.nextPlayerIndex);
            g0 = storeCallCard(g0, effect.callCard);
            g0 = storeLastMoveTimestamp(g0, uint40(block.timestamp));
        }

        emit MoveExecuted(gameId, moveParams.currentPlayerIndex, moveParams.gameAction);
        return (g0, g1);
    }

    function goToMarketOrPick(
        uint256 gameId,
        GameData storage game,
        Action action,
        uint256 currentIndex,
        CacheValue g0,
        CacheValue g1
    ) internal returns (CacheValue, CacheValue) {
        PlayerData storage playerSlot = game.players[currentIndex];
        PlayerData memory player;
        // store only player address and deckMap.
        assembly ("memory-safe") {
            let value := sload(playerSlot.slot)
            mstore(player, and(value, ADDRESS_MASK))
            mstore(add(player, 0x20), and(shr(160, value), U64_MASK))
            mstore(add(player, 0x40), and(shr(224, value), U8_MASK))
        }

        DeckMap marketDeckMap = loadMarketDeckMap(g1);

        if (action.eqs(Action.GoToMarket)) {
            if (player.pendingAction.notEqs(PendingAction.None)) {
                revert ResolvePendingAction();
            }
            marketDeckMap = game.deal(player, currentIndex, marketDeckMap);
        } else {
            if (player.pendingAction.eqs(PendingAction.None)) {
                revert NoPendingAction();
            }
            // if player has a pending action, they pick the number of cards equal to their pending action.
            marketDeckMap = game.dealPickN(player, currentIndex, marketDeckMap, uint8(player.pendingAction));
            // clear pending action.
            game.players[currentIndex].pendingAction = PendingAction.None;
            emit PendingActionFulfilled(gameId, currentIndex, player.pendingAction);
        }

        // compute next turn index.
        uint8 nextIdx = loadRuleset(g1).computeNextTurnIndex(loadPlayerStoreMap(g0), currentIndex);
        // update player turn index here.
        g0 = storePlayerTurnIndex(g0, nextIdx);
        g0 = storeLastMoveTimestamp(g0, uint40(block.timestamp));
        // g0.toStorage(slot0);

        emit MoveExecuted(gameId, currentIndex, Action.Pick);
        return (g0, g1);
    }

    function _applyEffect(
        GameData storage game,
        IRuleset.Effect memory effect,
        PlayerStoreMap playerStoreMap,
        DeckMap marketDeckMap
    ) internal returns (DeckMap) {
        // apply effect against player if any.
        IRuleset.EngineOp op = effect.op;
        if (op.notEqs(IRuleset.EngineOp.None)) {
            uint8 _op = uint8(op);
            bool dealPending = _op > 8;
            uint8 againstPlayerIdx = effect.againstPlayerIndex;

            if (playerStoreMap.isEmpty(againstPlayerIdx)) {
                revert InvalidPlayerIndex();
            }

            // `PendingPick` vs `Pick`: `PendingPick` are `Pick` actions that are not resolved immediately, but must be resolved
            // by the affected player on their turn before they can perform any other action.

            // if `againstPlayerIdx` is not type(uint8).max, then apply effect against only `againstPlayerIdx`.
            // otherwise, apply effect against all players.
            if (againstPlayerIdx != type(uint8).max) {
                if (dealPending) {
                    // if dealPending is true, then the against player is dealt the pending pick.
                    game.dealPendingPickN(againstPlayerIdx, _op - 8);
                } else {
                    // otherwise, the against player is dealt the normal pick.
                    PlayerData memory againstPlayer = game.players[againstPlayerIdx];
                    marketDeckMap = game.dealPickN(againstPlayer, againstPlayerIdx, marketDeckMap, _op);
                }
            } else {
                if (dealPending) {
                    // if dealPending is true, then all players are dealt the pending general market pick.
                    game.dealPendingGeneralMarket(againstPlayerIdx, _op - 8, playerStoreMap);
                } else {
                    // otherwise, all players are dealt the normal general market pick.
                    marketDeckMap = game.dealGeneralMarket(againstPlayerIdx, _op, marketDeckMap, playerStoreMap);
                }
            }
        }
        return marketDeckMap;
    }

    function ensurePlayerTurn(address currentPlayer) internal view {
        if (currentPlayer != msg.sender) revert NotPlayerTurn();
    }

    function ensureGameStarted(GameStatus currentStatus) internal pure {
        if (currentStatus.notEqs(GameStatus.Started)) revert GameNotStarted();
    }

    function ensureNoCommittedAction(uint256 gameId) internal view {
        if (hasCommittedAction(gameId)) revert PlayerAlreadyCommittedAction();
    }

    function getPlayerHand(uint256 gameId, uint256 playerIndex) external view returns (DeckMap, euint256[2] memory) {
        PlayerData memory player = cardGame[gameId].players[playerIndex];
        return (player.deckMap, player.hand);
    }

    function getPlayerData(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (address playerAddr, DeckMap deckMap, PendingAction pendingAction, uint16 score)
    {
        PlayerData memory player = cardGame[gameId].players[playerIndex];
        playerAddr = player.playerAddr;
        deckMap = player.deckMap;
        pendingAction = player.pendingAction;
        score = player.score;
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
            PlayerStoreMap playerStoreMap,
            IRuleset ruleset,
            DeckMap marketDeckMap
        )
    {
        // GameData storage game = cardGame[gameId];
        // (CacheValue g,) = loadCache(game, 0);

        // gameCreator = loadGameCreator(g);
        // callCard = loadCallCard(g);
        // playerTurnIdx = loadPlayerTurnIndex(g);
        // status = loadStatus(g);
        // lastMoveTimestamp = loadLastMoveTimestamp(g);
        // playerStoreMap = loadPlayerStoreMap(g);

        // (g,) = loadCache(game, 1);
        // ruleset = loadRuleset(g);
        // marketDeckMap = loadMarketDeckMap(g);
    }
}
