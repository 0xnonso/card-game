// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {euint256, euint8} from "@fhevm/solidity/lib/FHE.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

import {AsyncHandler} from "./base/AsyncHandler.sol";
import {EInputData, EInputHandler} from "./base/EInputHandler.sol";
import {ADDRESS_MASK, U16_MASK, U64_MASK, U8_MASK} from "./helpers/Constants.sol";
import {ICardEngine} from "./interfaces/ICardEngine.sol";
import {IManagerHook, IManagerView} from "./interfaces/IManager.sol";
import {IRuleset} from "./interfaces/IRuleSet.sol";
import {Action, CardEngineLib, GameData, GameStatus, PendingAction, PlayerData} from "./libraries/CardEngineLib.sol";
import {ConditionalsLib} from "./libraries/ConditionalsLib.sol";
import {Cache, CacheManager, CacheValue, GameCacheManager} from "./types/Cache.sol";
import {Card, CardLib} from "./types/Card.sol";
import {Hook, HookPermissions} from "./types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "./types/Map.sol";

import "hardhat/console.sol";

contract CardEngine is ICardEngine, EInputHandler, AsyncHandler, ReentrancyGuard {
    using ConditionalsLib for *;
    using GameCacheManager for Cache;
    using Hook for IManagerHook;
    using Hook for IManagerView;

    uint256 constant MAX_DELAY = 4 minutes;
    // Max number of players in a game.
    uint256 constant MAX_PLAYERS_LEN = 8;
    uint256 constant MIN_PLAYERS_LEN = 2;

    // game ID
    uint256 internal _gameId = 1;

    // Game Data.
    mapping(uint256 gameId => GameData) private _game;

    /// ERRORS
    error PlayerAlreadyInGame();
    error PlayerNotInGame();
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
    event PendingActionFulfilled(uint256 indexed gameId, uint256 playerIndex, uint8 action);
    event GameCreated(uint256 indexed gameId, address gameCreator);
    event GameStarted(uint256 indexed gameId);
    event GameEnded(uint256 indexed gameId);

    constructor() AsyncHandler() {}

    function createGame(CreateGameParams calldata params) public returns (uint256 gameId) {
        gameId = _gameId;
        GameData storage game = _game[gameId];
        // if proposed players is set, then max players is the length of proposed players.
        // if proposed players is not set, then max players is the max players passed in.
        uint8 numProposedPlayers = uint8(params.proposedPlayers.length);
        uint8 maxPlayers = numProposedPlayers != 0 ? numProposedPlayers : params.maxPlayers;

        if (maxPlayers > MAX_PLAYERS_LEN) revert PlayersLimitExceeded();
        if (maxPlayers < MIN_PLAYERS_LEN) revert PlayersLimitNotMet();

        for (uint256 i = 0; i < numProposedPlayers; i++) {
            address proposedPlayer = params.proposedPlayers[i];
            if (msg.sender == proposedPlayer) revert InvalidProposedPlayer();
            game.isProposedPlayer[proposedPlayer] = true;
        }
        // load storage value from game slot + index 1.
        Cache memory g = GameCacheManager.ldCache(slot1(game));

        g.sdRuleset(params.gameRuleset);
        if (!params.gameRuleset.supportsCardSize(params.cardBitSize)) {
            revert CardSizeNotSupported();
        }
        // initialize market deck map with card size and deck size.
        g.sdMarketDeckMap(CardEngineLib.initializeMarketDeckMap(params.cardDeckSize, params.cardBitSize));
        g.sdHandSize(params.initialHandSize); // set initial hand size.
        g.flush();
        // load storage value from game slot + index 0.
        g = GameCacheManager.ldCache(slot0(game));
        g.sdMaxPlayers(maxPlayers); // set max players.
        g.sdNumProposedPlayers(numProposedPlayers);
        g.sdPlayersLeftToJoin(maxPlayers); // initially, players left to join is max players.
        // `gameCreator` is the msg.sender if `enableManager` is true, otherwise it's address(0).
        g.sdGameCreator(msg.sender);
        g.sdHookPermissions(params.hookPermissions); // set initial hand size.
        g.flush();
        // initialize market deck.
        euint256[2] memory marketDeck = _handleInputData(params.inputData, params.inputProof);
        game.marketDeck[0] = marketDeck[0];
        game.marketDeck[1] = marketDeck[1];

        unchecked {
            _gameId++;
        }

        emit GameCreated(gameId, msg.sender);
    }

    function joinGame(uint256 gameId) public nonReentrant {
        GameData storage game = _game[gameId];
        // load storage value from game slot + index 0.
        Cache memory g = GameCacheManager.ldCache(slot0(game));

        if (g.ldStatus().notEqs(GameStatus.None)) revert GameAlreadyStarted();

        address playerToAdd = msg.sender;
        PlayerStoreMap playerStoreMap = g.ldPlayerStoreMap();
        uint8 playersLeftToJoin = g.ldPlayersLeftToJoin();
        address gameCreator = g.ldGameCreator();
        // use player store map to check if player is already in game.
        if (game.isPlayerActive(playerToAdd, playerStoreMap)) {
            revert PlayerAlreadyInGame();
        }
        if (playerToAdd == gameCreator) revert InvalidProposedPlayer();
        // if player is not a proposed player and `proposed players` is not set, then check if max players limit has been reached.
        // if proposed players is set (i.e proposed players array > 0), then check if player is in the proposed players list.
        bool isProposedPlayer =
            g.ldNumProposedPlayers() != 0 ? game.isProposedPlayer[playerToAdd] : playersLeftToJoin != 0;

        if (isProposedPlayer) {
            playerStoreMap = game.addPlayer(playerToAdd, playerStoreMap);
            playersLeftToJoin--;
            g.sdPlayersLeftToJoin(playersLeftToJoin);
            g.sdPlayerStoreMap(playerStoreMap);
            g.flush();
        } else {
            revert NotProposedPlayer(playerToAdd);
        }
        // call `onJoinGame` hook.
        IManagerHook(gameCreator).onJoinGame(g.ldHookPermissions(), gameId, playerToAdd);
        emit PlayerJoined(gameId, playerToAdd);
    }

    function startGame(uint256 gameId) external {
        GameData storage game = _game[gameId];
        // load storage value from game slot + index 0.
        Cache memory g0 = GameCacheManager.ldCache(slot0(game));
        // load storage value from game slot + index 1.
        Cache memory g1 = GameCacheManager.ldCache(slot1(game));

        address gameCreator = g0.ldGameCreator();
        uint256 playersLeftToJoin = g0.ldPlayersLeftToJoin();
        uint256 joined = g0.ldMaxPlayers() - playersLeftToJoin;

        {
            // can only start game if:
            //  - `playersLeftToJoin` is zero (i.e all players have joined).
            //  - game creator is the caller and at least 2 players have joined.
            bool canStartGame;
            assembly ("memory-safe") {
                // forgefmt: disable-next-item
                canStartGame := or(
                    iszero(playersLeftToJoin),
                    and(eq(caller(), gameCreator), gt(joined, 0x01))
                )
            }
            // if game can start, all players are dealt an initial hand, and each player's score is set to the minimum value of 65,535.
            if (!canStartGame) {
                revert CannotStartGame();
            }
            g0.sdStatus(GameStatus.Started);
            // set player turn index to the computed start index from .
            g0.sdPlayerTurnIndex(g1.ldRuleset().computeStartIndex(g0.ldPlayerStoreMap()));
            g0.flush();
        }

        DeckMap marketDeckMap = g1.ldMarketDeckMap();
        uint8 handSize = g1.ldHandSize();
        uint256 playersLen = g0.ldPlayerStoreMap().len();

        for (uint256 i = 0; i < playersLen; i++) {
            game.setPlayerScoreToMin(i);
            // deal all players the initial hand.
            marketDeckMap = game.dealInitialHand(game.players[i], i, marketDeckMap, joined, handSize);
        }

        // game.marketDeckMap = marketDeckMap;
        g1.sdMarketDeckMap(marketDeckMap);
        g1.flush();

        emit GameStarted(gameId);

        // - call `onStartGame` hook.
        // at this point, the game might end immediately if the call to the hook returns true.
        // this is to allow the game manager to force end a game if needed (i.e if the game does not require any moves to be played).
        bool endGame = IManagerHook(gameCreator).onStartGame(g0.ldHookPermissions(), gameId);
        finish(gameId, game, endGame, g0, g1);
    }

    function commitMove(uint256 gameId, Action action, uint256 cardIndex, bytes memory extraData) external {
        ensureNoCommittedAction(gameId);

        GameData storage game = _game[gameId];
        // load storage value from game slot + index 0.
        Cache memory g = GameCacheManager.ldCache(slot0(game));

        ensureGameStarted(g.ldStatus());

        uint256 currentTurnIndex = g.ldPlayerTurnIndex();
        PlayerData storage _player = game.players[currentTurnIndex];
        uint256 playerSlot;
        // store only player address and deckMap.
        assembly ("memory-safe") {
            playerSlot := _player.slot
        }
        // mstore(player, and(value, ADDRESS_MASK))
        // mstore(add(player, 0x20), and(shr(160, value), U64_MASK))
        CacheValue playerCache = CacheManager.toCachedValue(playerSlot);
        // load player's address at pos 0.
        address playerAddr = playerCache.loadAddress(0);
        // load player's address at pos 160.
        DeckMap playerDeckMap = DeckMap.wrap(playerCache.loadU64(160));

        ensureValidPlayer(game, playerAddr, g.ldPlayerStoreMap());

        if (!action.eqsOr(Action.Play, Action.Defend)) {
            revert InvalidGameAction(action);
        }
        // get card to commit and updated player deck map.
        euint8 cardToCommit = game.getCardToCommit(playerDeckMap, cardIndex);
        _commitMove(gameId, cardToCommit, action, cardIndex, currentTurnIndex, extraData);
    }

    function executeMove(uint256 gameId, Action action, bytes memory extraData) external nonReentrant {
        GameData storage game = _game[gameId];
        // load storage value from game slot + index 0.
        Cache memory g0 = GameCacheManager.ldCache(slot0(game));
        // load storage value from game slot + index 1.
        Cache memory g1 = GameCacheManager.ldCache(slot1(game));

        uint8 playerTurnIdx = g0.ldPlayerTurnIndex();
        PlayerData memory player = game.players[playerTurnIdx];

        ensureGameStarted(g0.ldStatus());
        ensureValidPlayer(game, player.playerAddr, g0.ldPlayerStoreMap());
        ensureNoCommittedAction(gameId);

        if (action.eqsOr(Action.Play, Action.Defend)) {
            revert InvalidGameAction(action);
        }
        // if action is draw, player must not have a pending action.
        // if action is Pick, player must have a pending action.
        drawOrPick(gameId, game, player, action, playerTurnIdx, g0, g1, extraData);
        // update storage slots.
        g0.flush();
        g1.flush();
        // call `onExecuteMove` hook with an empty card since no card is played.
        // Card(0) represents an invaild or empty card.
        bool canEndGame = IManagerHook(g0.ldGameCreator()).onExecuteMove(
            g0.ldHookPermissions(), gameId, player.playerAddr, CardLib.toCard(0), action
        );
        // finally, check if game can end.
        finish(gameId, game, canEndGame, g0, g1);
    }

    function forfeit(uint256 gameId) external {
        GameData storage game = _game[gameId];
        // load storage value from game slot + index 0.
        Cache memory g0 = GameCacheManager.ldCache(slot0(game));
        // load storage value from game slot + index 1.
        Cache memory g1 = GameCacheManager.ldCache(slot1(game));

        ensureGameStarted(g0.ldStatus());

        uint256 playerIdx = game.getPlayerIndex(msg.sender);
        _forfeit(gameId, game, playerIdx, g1.ldRuleset(), g0);
        g0.flush();
        finish(gameId, game, false, g0, g1);
    }

    function bootOut(uint256 gameId) external {
        GameData storage game = _game[gameId];
        // load storage value from game slot + index 0.
        Cache memory g0 = GameCacheManager.ldCache(slot0(game));

        ensureGameStarted(g0.ldStatus());

        uint256 turnIdx = g0.ldPlayerTurnIndex();
        uint40 lastMoveTimestamp = g0.ldLastMoveTimestamp();
        address player = game.players[turnIdx].playerAddr;
        // boot out a player if their last move timestamp + MAX_DELAY is less than the current block timestamp.
        // this is the default boot out condition if no hook is set.
        bool defaultCondition = (lastMoveTimestamp + MAX_DELAY) <= block.timestamp;
        // call `canBootOut` hook to check if player can be booted out.
        // this overrides the default boot out condition of `lastMoveTimestamp + MAX_DELAY <= block.timestamp`.
        bool canBootOut = IManagerView(g0.ldGameCreator()).canBootOut(
            g0.ldHookPermissions(), gameId, player, lastMoveTimestamp, defaultCondition
        );
        if (!canBootOut) revert CannotBootOutPlayer(player);
        // load storage value from game slot + index 1.
        Cache memory g1 = GameCacheManager.ldCache(slot1(game));

        _forfeit(gameId, game, turnIdx, g1.ldRuleset(), g0);
        g0.flush();
        finish(gameId, game, false, g0, g1);
    }

    function handleCommitMove(uint256 requestId, bytes memory clearTexts, bytes memory signatures)
        external
        virtual
        override
    {
        CommittedMoveData memory committedMove = getCommittedMove(requestId);
        // validate callback signature and that this is the latest request.
        __validateCallbackSignature(requestId, clearTexts, committedMove.gameId, signatures);
        GameData storage game = _game[committedMove.gameId];

        uint8 rawCard = abi.decode(clearTexts, (uint8));
        Card card = CardLib.toCard(rawCard);
        // load storage value from game slot + index 0.
        Cache memory g0 = GameCacheManager.ldCache(slot0(game));
        // load storage value from game slot + index 1.
        Cache memory g1 = GameCacheManager.ldCache(slot1(game));

        address gameCreator = g0.ldGameCreator();
        HookPermissions hookPermissions = g0.ldHookPermissions();
        PlayerData memory player = game.players[committedMove.playerIndex];
        // execute the move.
        playCard(game, player, committedMove, card, gameCreator, hookPermissions, g0, g1);
        // update storage slots.
        g0.flush();
        g1.flush();
        // if game creator is set, call `onExecuteMove` hook.
        bool endGame = IManagerHook(gameCreator).onExecuteMove(
            hookPermissions, committedMove.gameId, player.playerAddr, card, committedMove.action
        );
        // clean up commitment and check if game can end.
        _clearCommitment(committedMove.gameId, requestId);
        finish(committedMove.gameId, game, endGame, g0, g1);
    }

    function handleCommitMarketDeck(uint256 requestId, bytes memory clearTexts, bytes memory signatures)
        external
        virtual
        override
        nonReentrant
    {
        CommittedMarketDeck memory cmd = getCommittedMarketDeck(requestId);
        // validate callback signature and that this is the latest request.
        __validateCallbackSignature(requestId, clearTexts, cmd.gameId, signatures);
        GameData storage game = _game[cmd.gameId];
        uint256[2] memory marketDeck = abi.decode(clearTexts, (uint256[2]));

        uint256 playersLen = game.players.length;
        uint256[] memory playersData = new uint256[](playersLen);
        for (uint256 i = 0; i < playersLen; i++) {
            PlayerData memory player = game.players[i];
            if (!player.forfeited) {
                player.score = game.calculateAndSetPlayerScore(player, i, marketDeck);
            }
            playersData[i] = (uint256(player.score) << 224) | (uint256(DeckMap.unwrap(player.deckMap)) << 160)
                | uint256(uint160(player.playerAddr));
        }
        // call `onFinishGame` hook with players score data.
        // players score data is computed as packed [score, address] value for each player in the game.
        Cache memory g = GameCacheManager.ldCache(slot0(game));
        IManagerHook(g.ldGameCreator()).onFinishGame(g.ldHookPermissions(), cmd.gameId, playersData, marketDeck);
    }

    function finish(uint256 gameId, GameData storage game, bool preCondition, Cache memory g0, Cache memory g1)
        internal
    {
        bool playerStoreSingle = g0.ldPlayerStoreMap().len() == 1;
        bool gameMarketDeckEmpty = g1.ldMarketDeckMap().isMapEmpty();
        bool shouldEnd;
        assembly ("memory-safe") {
            shouldEnd := or(preCondition, or(playerStoreSingle, gameMarketDeckEmpty))
        }
        if (shouldEnd) {
            ensureNoCommittedAction(gameId);
            _commitMarketDeck(gameId, game.marketDeck);
            game.status = GameStatus.Ended;
            emit GameEnded(gameId);
        }
    }

    function playCard(
        GameData storage game,
        PlayerData memory player,
        CommittedMoveData memory committedMove,
        Card card,
        address gameCreator,
        HookPermissions hookPermissions,
        Cache memory g0,
        Cache memory g1
    ) internal {
        (player.deckMap, player.hand) =
            game.updatePlayerHand(player, committedMove.playerIndex, committedMove.cardIndex);
        IRuleset ruleset = g1.ldRuleset();
        // check if player is eligible for a special move. this is false by default if no hook is set.
        bool isEligibleForSpecialMove;
        if (ruleset.isSpecialMoveCard(card)) {
            isEligibleForSpecialMove = IManagerView(gameCreator).hasSpecialMoves(
                hookPermissions, committedMove.gameId, player.playerAddr, card, committedMove.action
            );
        }
        IRuleset.ResolveMoveParams memory moveParams = IRuleset.ResolveMoveParams({
            gameAction: committedMove.action,
            pendingAction: player.pendingAction,
            card: card,
            callCard: g0.ldCallCard(),
            currentPlayerIndex: committedMove.playerIndex,
            playerStoreMap: g0.ldPlayerStoreMap(),
            playerDeckMap: player.deckMap,
            playerHand: player.hand,
            isSpecial: isEligibleForSpecialMove,
            cardSize: g1.ldMarketDeckMap().getDeckCardSize(),
            extraData: committedMove.extraData
        });
        player.grantAccessToHand(address(ruleset));
        _executeMove(committedMove.gameId, game, ruleset, moveParams, g0, g1);
    }

    function drawOrPick(
        uint256 gameId,
        GameData storage game,
        PlayerData memory player,
        Action action,
        uint8 currentIndex,
        Cache memory g0,
        Cache memory g1,
        bytes memory extraData
    ) internal {
        IRuleset.ResolveMoveParams memory moveParams;
        moveParams.gameAction = action;
        moveParams.pendingAction = player.pendingAction;
        moveParams.callCard = g0.ldCallCard();
        moveParams.currentPlayerIndex = currentIndex;
        moveParams.playerStoreMap = g0.ldPlayerStoreMap();
        moveParams.playerDeckMap = player.deckMap;
        moveParams.playerHand = player.hand;
        moveParams.cardSize = g1.ldMarketDeckMap().getDeckCardSize();
        moveParams.extraData = extraData;

        IRuleset ruleset = g1.ldRuleset();
        player.grantAccessToHand(address(ruleset));
        _executeMove(gameId, game, ruleset, moveParams, g0, g1);
    }

    function _forfeit(uint256 gameId, GameData storage game, uint256 playerIdx, IRuleset ruleset, Cache memory g0)
        internal
    {
        g0.sdPlayerStoreMap(g0.ldPlayerStoreMap().removePlayer(playerIdx));
        game.players[playerIdx].forfeited = true;
        // if the forfeiting player is the current player, update the turn index to the next player.
        if (g0.ldPlayerTurnIndex() == playerIdx) {
            g0.sdPlayerTurnIndex(ruleset.computeNextTurnIndex(g0.ldPlayerStoreMap(), playerIdx));
            _clearLatestCommittedMove(gameId, playerIdx);
        }
        emit PlayerForfeited(gameId, playerIdx);
    }

    function _executeMove(
        uint256 gameId,
        GameData storage game,
        IRuleset ruleset,
        IRuleset.ResolveMoveParams memory moveParams,
        Cache memory g0,
        Cache memory g1
    ) internal {
        if (moveParams.pendingAction != 0) {
            game.players[moveParams.currentPlayerIndex].pendingAction = 0;
        }
        // resolve move and get effect.
        IRuleset.Effect memory effect = ruleset.resolveMove(moveParams);
        // apply effect to game state.
        _applyEffect(game, effect, moveParams.currentPlayerIndex, moveParams.playerStoreMap, g1);
        // update player turn index here.
        g0.sdPlayerTurnIndex(effect.nextPlayerIndex);
        g0.sdCallCard(effect.callCard);
        g0.sdLastMoveTimestamp(uint40(block.timestamp));

        if (moveParams.playerDeckMap.isMapEmpty() || effect.currentPlayerExit) {
            g0.sdPlayerStoreMap(moveParams.playerStoreMap.removePlayer(moveParams.currentPlayerIndex));
        }
        emit MoveExecuted(gameId, moveParams.currentPlayerIndex, moveParams.gameAction);
    }

    function _applyEffect(
        GameData storage game,
        IRuleset.Effect memory effect,
        uint256 currentPlayerIdx,
        PlayerStoreMap playerStoreMap,
        Cache memory g1
    ) internal {
        IRuleset.Action[] memory rActions = effect.actions;
        DeckMap marketDeckMap = g1.ldMarketDeckMap();

        for (uint256 i = 0; i < rActions.length; i++) {
            // apply effect against player if any.
            // IRuleset.EngineOp op = effect.op;
            if (rActions[i].op.notEqs(IRuleset.EngineOp.None)) {
                uint8 _op = uint8(rActions[i].op);
                bool dealPending = _op > 8;
                uint8 againstPlayerIdx = rActions[i].againstPlayerIndex;

                // `PendingPick` vs `Pick`: `PendingPick` are `Pick` actions that are not resolved immediately, but must be resolved
                // by the affected player on their turn before they can perform any other action.

                // if `againstPlayerIdx` is not type(uint8).max, then apply effect against only `againstPlayerIdx`.
                // otherwise, apply effect against all players.
                if (againstPlayerIdx != type(uint8).max) {
                    if (playerStoreMap.isEmpty(againstPlayerIdx)) {
                        revert InvalidPlayerIndex();
                    }
                    if (dealPending) {
                        // if `dealPending` is true, then the against player is dealt the pending pick.
                        game.dealPendingPickN(againstPlayerIdx, _op - 8);
                    } else {
                        // otherwise, the against player is dealt the normal pick.
                        // PlayerData memory againstPlayer = game.players[againstPlayerIdx];
                        if (_op == 1) {
                            marketDeckMap = game.deal(againstPlayerIdx, marketDeckMap);
                        } else {
                            marketDeckMap = game.dealPickN(againstPlayerIdx, marketDeckMap, _op);
                        }
                    }
                } else {
                    if (dealPending) {
                        // if `dealPending` is true, then all players are dealt the pending general market pick.
                        game.dealPendingGeneralMarket(currentPlayerIdx, _op - 8, playerStoreMap);
                    } else {
                        // otherwise, all players are dealt the normal general market pick.
                        marketDeckMap = game.dealGeneralMarket(currentPlayerIdx, _op, marketDeckMap, playerStoreMap);
                    }
                }
            }
        }
        g1.sdMarketDeckMap(marketDeckMap);
    }

    function ensureValidPlayer(GameData storage game, address currentPlayer, PlayerStoreMap playerStoreMap)
        internal
        view
    {
        uint256 playerIndex = game.getPlayerIndex(msg.sender);
        if (playerStoreMap.isEmpty(playerIndex)) revert PlayerNotInGame();
        if (currentPlayer != msg.sender) revert NotPlayerTurn();
    }

    function ensureGameStarted(GameStatus currentStatus) internal pure {
        if (currentStatus.notEqs(GameStatus.Started)) revert GameNotStarted();
    }

    function ensureNoCommittedAction(uint256 gameId) internal view {
        if (hasCommittedAction(gameId)) revert PlayerAlreadyCommittedAction();
    }

    function slot0(GameData storage game) internal pure returns (uint256 slot0_) {
        assembly ("memory-safe") {
            slot0_ := game.slot
        }
    }

    function slot1(GameData storage game) internal pure returns (uint256 slot1_) {
        assembly ("memory-safe") {
            slot1_ := add(game.slot, 1)
        }
    }

    function getPlayerHand(uint256 gameId, uint256 playerIndex) external view returns (DeckMap, euint256[2] memory) {
        PlayerData memory player = _game[gameId].players[playerIndex];
        return (player.deckMap, player.hand);
    }

    function getPlayerData(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (address playerAddr, DeckMap deckMap, uint8 pendingAction, uint16 score, euint256[2] memory hand)
    {
        PlayerData memory player = _game[gameId].players[playerIndex];
        playerAddr = player.playerAddr;
        deckMap = player.deckMap;
        pendingAction = player.pendingAction;
        score = player.score;
        hand = player.hand;
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
        GameData storage game = _game[gameId];
        Cache memory g = GameCacheManager.ldCache(slot0(game));

        gameCreator = g.ldGameCreator();
        callCard = g.ldCallCard();
        playerTurnIdx = g.ldPlayerTurnIndex();
        status = g.ldStatus();
        lastMoveTimestamp = g.ldLastMoveTimestamp();
        playerStoreMap = g.ldPlayerStoreMap();

        g = GameCacheManager.ldCache(slot1(game));
        ruleset = g.ldRuleset();
        marketDeckMap = g.ldMarketDeckMap();
    }
}
