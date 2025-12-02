// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {euint256, euint8} from "@fhevm/solidity/lib/FHE.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

import {AsyncHandler} from "./base/AsyncHandler.sol";
import {EInputData, EInputHandler} from "./base/EInputHandler.sol";
import {Constants} from "./helpers/Constants.sol";
import {ICardEngine} from "./interfaces/ICardEngine.sol";
import {IManagerHook, IManagerView} from "./interfaces/IManager.sol";
import {IRuleset} from "./interfaces/IRuleset.sol";
import {Action, CardEngineLib, GameData, GameStatus, PlayerData, PlayerScoreData} from "./libraries/CardEngineLib.sol";
import {ConditionalsLib} from "./libraries/ConditionalsLib.sol";
import {Card, CardLib} from "./types/Card.sol";
import {Hook, HookPermissions} from "./types/Hook.sol";
import {DeckMap, PlayerStoreMap} from "./types/Map.sol";

contract CardEngine is ICardEngine, EInputHandler, AsyncHandler, ReentrancyGuard {
    using ConditionalsLib for *;
    using Hook for IManagerHook;
    using Hook for IManagerView;

    uint256 private gId = 1; // game id counter.
    mapping(uint256 gameId => GameData) private gd; // game data mapping.

    /// ERRORS
    error PlayerAlreadyInGame();
    error PlayerNotInGame();
    error GameAlreadyStarted();
    error GameNotStarted();
    error InvalidPlayerAddress(address addr);
    error ResolvePendingAction();
    error NotProposedPlayer(address player);
    error CannotStartGame();
    error PlayersLimitExceeded();
    error PlayersLimitNotMet();
    error CannotBootOutPlayer(address player);
    error InvalidGameAction(Action action);
    error PlayerAlreadyCommittedAction();
    error InvalidPlayerIndex();
    error CardSizeNotSupported();
    error CardDeckSizeTooSmall();

    /// EVENTS
    event PlayerForfeited(uint256 indexed gameId, uint256 playerIndex);
    event PlayerBootedOut(uint256 indexed gameId, uint256 playerIndex);
    event PlayerJoined(uint256 indexed gameId, address player);
    event MoveExecuted(uint256 indexed gameId, uint256 pTurnIndex, Action action);
    event GameCreated(uint256 indexed gameId, address gameCreator);
    event GameStarted(uint256 indexed gameId);
    event GameEnded(uint256 indexed gameId);
    event MoveCommitted(uint256 indexed gameId, uint256 playerIndex, Action action);
    event PlayersDealtInitialHand(uint256 indexed gameId, uint8 handSize);
    event PlayerDealtPending(uint256 indexed gameId, uint256 playerIndex, uint8 pendingN);
    event PlayerDealt(uint256 indexed gameId, uint256 playerIndex, uint8 n);
    event PlayersDealtGeneralPending(uint256 indexed gameId, uint8 pendingN);
    event PlayersDealtGeneral(uint256 indexed gameId, uint8 n);

    constructor() AsyncHandler() {}

    /// GAME ACTION FUNCTIONS

    /// @dev Creates a new game with the specified parameters and returns the game ID.
    ///
    /// This function initializes the game state, including the market deck, ruleset, and proposed players.
    /// It can create a game that allows up to `params.maxPlayers` players to join, or restricts joining to
    /// a predefined list of `params.proposedPlayers`.
    ///
    /// Caller of this function is set as the game creator (manager), with hook permissions defined by `params.hookPermissions`
    /// that determines which hooks can be called during the game lifecycle.
    ///
    /// The ruleset must support the specified card bit size (`params.cardBitSize`) and card deck size (`params.cardDeckSize`);
    /// otherwise, the function will revert.
    /// Card bit size is the bit width of each card in the deck. The maximum card bit size is 8 bits, while the minimum is 5 bits.
    /// A `params.cardBitSize` value of 0 represents 8-bit, 1 represents 7-bit, and so on down to 5-bit.
    /// The card deck size is the total number of cards in the deck. The maximum deck size is 62 cards, and the total number of cards
    /// must be sufficient to deal the initial hand size to all players.
    ///
    /// `params.input0`, `params.input1`, and `params.inputProof` are used to initialize the encrypted market deck. If (deck size * bit size)
    /// is less than or equals 256 bits, then `params.input1` can be empty. But param.input0 cannot be empty.
    function createGame(CreateGameParams calldata params) public returns (uint256 gameId) {
        gameId = gId;
        GameData storage game = gd[gameId];
        // if proposed players is set, then max players is the length of proposed players.
        // if proposed players is not set, then max players is the max players passed in.
        uint8 numProposedPlayers = uint8(params.proposedPlayers.length);
        uint8 maxPlayers = numProposedPlayers != 0 ? numProposedPlayers : params.maxPlayers;

        if (maxPlayers > Constants.MAX_PLAYERS_LEN) revert PlayersLimitExceeded();
        if (maxPlayers < Constants.MIN_PLAYERS_LEN) revert PlayersLimitNotMet();

        for (uint256 i = 0; i < numProposedPlayers; i++) {
            address proposedPlayer = params.proposedPlayers[i];
            game.isProposedPlayer[proposedPlayer] = true;
        }

        require(params.initialHandSize != 0);

        if (!params.gameRuleset.supportsCardSize(params.cardBitSize)) revert CardSizeNotSupported();
        game.ruleset = params.gameRuleset;

        // initialize market deck map with card size and deck size.
        DeckMap marketDeckMap = CardEngineLib.initializeMarketDeckMap(params.cardDeckSize, params.cardBitSize);
        if ((params.initialHandSize * maxPlayers) > marketDeckMap.len()) {
            revert CardDeckSizeTooSmall();
        }
        game.marketDeckMap = marketDeckMap;
        game.initialHandSize = params.initialHandSize; // set initial hand size.
        game.numProposedPlayers = numProposedPlayers;
        game.playersLeftToJoin = maxPlayers; // initially, players left to join is max players.
        game.gameCreator = msg.sender; // set `gameCreator` as msg.sender.
        game.hookPermissions = params.hookPermissions; // set initial hand size.

        // initialize market deck.
        euint256[2] memory marketDeck = _handleInputData(params.input0, params.input1, params.inputProof);
        game.marketDeck[0] = marketDeck[0];
        game.marketDeck[1] = marketDeck[1];

        unchecked {
            gId++;
        }

        emit GameCreated(gameId, msg.sender);
    }

    /// @dev Allows a player to join an existing game.
    ///
    /// If the proposed number of players is set during game creation, only those players can join.
    /// else, any player can join until the max players limit is reached.
    function joinGame(uint256 gameId) public nonReentrant {
        GameData storage game = gd[gameId];

        if (game.status.notEqs(GameStatus.None)) revert GameAlreadyStarted();

        address playerToAdd = msg.sender;
        PlayerStoreMap playerStoreMap = game.playerStoreMap;
        uint8 playersLeftToJoin = game.playersLeftToJoin;
        address gameCreator = game.gameCreator;
        // check if player is already in game.
        if (game.isPlayerActive(playerToAdd, playerStoreMap)) revert PlayerAlreadyInGame();
        // if player is not a proposed player and `proposed players` is not set, then check if max players limit has been reached.
        // if proposed players is set (i.e proposed players array > 0), then check if player is in the proposed players list.
        bool isProposedPlayer =
            game.numProposedPlayers != 0 ? game.isProposedPlayer[playerToAdd] : playersLeftToJoin != 0;

        if (isProposedPlayer) {
            playerStoreMap = game.addPlayer(playerToAdd, playerStoreMap);
            playersLeftToJoin--;
            game.playersLeftToJoin = playersLeftToJoin;
            game.playerStoreMap = playerStoreMap;
        } else {
            revert NotProposedPlayer(playerToAdd);
        }
        // - call `onJoinGame` hook.
        IManagerHook(gameCreator).onJoinGame(game.hookPermissions, gameId, playerToAdd);
        emit PlayerJoined(gameId, playerToAdd);
    }

    /// @dev Starts a game that has been created and joined by players.
    ///
    /// Starts the game if all proposed players or max players have joined. If not all players have joined, only the game
    /// creator can force start the game.
    /// Players are dealt their initial hands, and the game status is updated.
    /// Also, this triggers the `onStartGame` hook, which can potentially end the game immediately.
    function startGame(uint256 gameId) external {
        GameData storage game = gd[gameId];

        address gameCreator = game.gameCreator;
        uint256 playersLeftToJoin = game.playersLeftToJoin;
        uint256 joined = game.playerStoreMap.len();

        // can only start game if:
        //  - `playersLeftToJoin` is zero (i.e all players have joined).
        //  - game creator is the caller and at least 2 players have joined.
        bool canStartGame;
        assembly {
            // forgefmt: disable-next-item
            canStartGame := or(iszero(playersLeftToJoin), and(eq(caller(), gameCreator), gt(joined, 0x01)))
        }
        // if game can start, all players are dealt an initial hand, and each player's score is set to the minimum value of 65,535.
        if (!canStartGame) {
            revert CannotStartGame();
        }
        game.status = GameStatus.Started;
        game.playerTurnIdx = game.ruleset.computeStartIndex(game.playerStoreMap);

        DeckMap marketDeckMap = game.marketDeckMap;
        uint8 handSize = game.initialHandSize;

        for (uint256 i = 0; i < joined; i++) {
            // deal all players the initial hand.
            marketDeckMap = game.dealInitialHand(i, marketDeckMap, joined, handSize);
        }
        emit PlayersDealtInitialHand(gameId, handSize);

        game.marketDeckMap = marketDeckMap;
        _initializeEngineCallback(gameId);

        emit GameStarted(gameId);

        // - call `onStartGame` hook.
        // at this point, the game might end immediately if the call to the hook returns true.
        // this is to allow the game manager to force end a game if needed (i.e if the game does not require any moves to be played).
        bool endGame = IManagerHook(gameCreator).onStartGame(game.hookPermissions, gameId);
        finish(gameId, game, endGame);
    }

    /// @dev Commits a move for the current player in the specified game.
    ///
    /// If a player intends to play or defend with a card, they must first commit the card so that it can be decrypted.
    ///
    /// Note: Currently, the contract does not verify that the card to commit is valid under the game rules, so the player is expected
    /// to commit the correct card, since there is no way to back out of a committed move.
    /// Penalty for committing a wrong card is mostly handled by the game ruleset or the game manager via the `canBootOut` hook.
    function commitMove(uint256 gameId, Action action, uint256 cardIndex) external {
        GameData storage game = gd[gameId];

        ensureNoCommittedAction(gameId);
        ensureGameStarted(game.status);

        uint8 currentTurnIndex = game.playerTurnIdx;
        PlayerData memory player = game.players[currentTurnIndex];

        ensureValidCaller(player.playerAddr, currentTurnIndex, game.playerStoreMap);

        if (!action.eqsOr(Action.Play, Action.Defend)) {
            revert InvalidGameAction(action);
        }
        // get card to commit.
        euint8 cardToCommit = game.getCardToCommit(player.deckMap, cardIndex);
        _commitMove(gameId, cardToCommit, action, cardIndex, currentTurnIndex);
    }

    /// @dev Executes a move for the current player in the specified game.
    ///
    /// Executing a move involves resolving the player's action according to the game ruleset. Some actions require a committed move.
    /// i.e Play, Defend.
    /// The ruleset is granted access to the player's hand in case it needs access to it to resolve the move.
    ///
    /// Game can end after executing a move based on the return value of the `onExecuteMove` hook.
    function executeMove(uint256 gameId, Action action, bytes memory extraData) external nonReentrant {
        GameData storage game = gd[gameId];

        uint8 playerTurnIdx = game.playerTurnIdx;
        PlayerData memory player = game.players[playerTurnIdx];
        PlayerStoreMap playerStoreMap = game.playerStoreMap;

        ensureGameStarted(game.status);
        ensureValidCaller(player.playerAddr, playerTurnIdx, playerStoreMap);

        HookPermissions hookPermissions = game.hookPermissions;
        address gameCreator = game.gameCreator;
        IRuleset ruleset = game.ruleset;
        Card card;
        bool isSpecialCard;

        // actions {PLAY, DEFEND} require a committed move; you must commit a card before calling `executeMove`.
        // but they’re still declarative: the engine enforces nothing beyond the commitment; the ruleset decides the rest.
        // the other actions {DRAW, NEUTRAL} are purely declarative (no commit) and are interpreted by the ruleset.

        if (action.eqsOr(Action.Play, Action.Defend)) {
            CommittedMoveData memory committedMove = getLatestCommittedMove(gameId);
            card = committedMove.decryptedCard;
            action = committedMove.action;
            (player.deckMap, player.hand) = game.updatePlayerHand(player, playerTurnIdx, committedMove.cardIndex);
            // check if player is eligible for a special move. this is false by default if no hook is set.
            if (ruleset.isSpecialMoveCard(card)) {
                isSpecialCard = IManagerView(gameCreator).hasSpecialMoves(
                    hookPermissions, gameId, player.playerAddr, card, committedMove.action
                );
            }
            // clean up commitment.
            _clearLatestCommittedMove(gameId);
        } else {
            ensureNoCommittedAction(gameId);
        }

        IRuleset.ResolveMoveParams memory moveParams = IRuleset.ResolveMoveParams({
            gameAction: action,
            pendingAction: player.pendingAction,
            card: card,
            callCard: game.callCard,
            currentPlayerIndex: playerTurnIdx,
            playerStoreMap: playerStoreMap,
            cardSize: game.marketDeckMap.getDeckCardSize(),
            playerDeckMap: player.deckMap,
            playerHand: player.hand,
            isSpecial: isSpecialCard,
            extraData: extraData
        });

        CardEngineLib.grantAccessToHand(player.hand, address(ruleset));
        _executeMove(gameId, game, gameCreator, hookPermissions, ruleset, moveParams);

        // call `onExecuteMove` hook with an empty card since no card is played.
        // Card(0) represents an invaild/empty card or a wild card.
        bool canEndGame = IManagerHook(gameCreator).onExecuteMove(
            hookPermissions, gameId, player.playerAddr, moveParams.card, moveParams.gameAction
        );
        // finally, check if game can end.
        finish(gameId, game, canEndGame);
    }

    /// @dev Allows a player to forfeit the game they are currently in.
    ///
    /// When a player forfeits, they are removed from the game and marked as forfeited.
    function forfeit(uint256 gameId) external nonReentrant {
        GameData storage game = gd[gameId];

        ensureGameStarted(game.status);

        uint256 playerIdx = game.getPlayerIndex(msg.sender);
        address playerAddr = game.players[playerIdx].playerAddr;
        PlayerStoreMap playerStoreMap = game.playerStoreMap;

        ensureValidCaller(playerAddr, uint8(playerIdx), playerStoreMap);

        _forfeit(gameId, game, playerAddr, playerIdx, playerStoreMap, game.gameCreator, game.ruleset);
        finish(gameId, game, false);

        emit PlayerForfeited(gameId, playerIdx);
    }

    /// @dev Boots out a player from the specified game.
    ///
    /// A player can be booted out if they have exceeded the allowed delay for making a move.
    /// But this is the default condition and the game manager can override this via the `canBootOut` hook.
    /// Anyone can call this function to boot a player out if the conditions are met.
    function bootOut(uint256 gameId, uint256 playerIdx) external nonReentrant {
        GameData storage game = gd[gameId];

        ensureGameStarted(game.status);

        address playerAddr = game.players[playerIdx].playerAddr;
        PlayerStoreMap playerStoreMap = game.playerStoreMap;
        if (playerStoreMap.isEmpty(playerIdx)) revert PlayerNotInGame();

        // if player has a committed move that is not yet fulfilled, revert.
        if (
            hasCommittedMove(gameId) && !getCommittedMove(gameId).fulfilled
                && playerIdx == getCommittedMove(gameId).playerIndex
        ) {
            revert PlayerAlreadyCommittedAction();
        }
        uint40 lastMoveTimestamp = game.lastMoveTimestamp;
        // boot out a player if their last move timestamp + MAX_DELAY is less than the current block timestamp.
        // this is the default boot out condition if no hook is set.
        bool defaultCondition = (lastMoveTimestamp + Constants.MAX_DELAY) <= block.timestamp;
        // call `canBootOut` hook to check if player can be booted out.
        // this overrides the default boot out condition of `lastMoveTimestamp + MAX_DELAY <= block.timestamp`.
        address gameCreator = game.gameCreator;
        HookPermissions hookPermissions = game.hookPermissions;
        bool canBootOut = IManagerView(gameCreator).canBootOut(
            hookPermissions, gameId, playerAddr, lastMoveTimestamp, defaultCondition
        );
        if (!canBootOut) revert CannotBootOutPlayer(playerAddr);

        _forfeit(gameId, game, playerAddr, playerIdx, playerStoreMap, gameCreator, game.ruleset);
        finish(gameId, game, false);

        emit PlayerBootedOut(gameId, playerIdx);
    }

    /// CALLBACK FUNCTIONS

    /// @dev Handles the callback for a committed move.
    function handleCommitMove(uint256 requestId, bytes memory clearTexts, bytes memory signatures)
        external
        virtual
        override
    {
        CommittedMoveData memory committedMove = getCommittedMove(requestId);
        uint256 gameId = committedMove.gameId;
        // validate the callback signature and ensure this is the latest request.
        __validateCallbackSignature(requestId, clearTexts, gameId, signatures, true);
        _fulfillCommittedMove(requestId, clearTexts);
        // update last move timestamp.
        gd[gameId].lastMoveTimestamp = uint40(block.timestamp);
        emit MoveCommitted(gameId, committedMove.playerIndex, committedMove.action);
    }

    /// @dev Handles the callback for a committed market deck.
    function handleCommitMarketDeck(uint256 requestId, bytes memory clearTexts, bytes memory signatures)
        external
        virtual
        override
        nonReentrant
    {
        CommittedMarketDeck memory cmd = getCommittedMarketDeck(requestId);
        // validate the callback signature and ensure this is the latest request.
        __validateCallbackSignature(requestId, clearTexts, cmd.gameId, signatures, false);
        GameData storage game = gd[cmd.gameId];
        uint256[2] memory marketDeck = abi.decode(clearTexts, (uint256[2]));

        DeckMap marketDeckMap = game.marketDeckMap;
        IRuleset ruleset = game.ruleset;

        uint256 playersLen = game.players.length;
        PlayerScoreData[] memory playersData = new PlayerScoreData[](playersLen);
        for (uint256 i = 0; i < playersLen; i++) {
            PlayerData memory player = game.players[i];
            uint16 playerScore;
            if (!player.forfeited) {
                (marketDeckMap, player.deckMap) =
                    game.resolvePending(i, marketDeckMap, player.deckMap, player.pendingAction);
                playerScore = game.calculateAndSetPlayerScore(i, marketDeckMap, player.deckMap, marketDeck, ruleset);
            }
            playersData[i] =
                PlayerScoreData({playerAddr: player.playerAddr, deckMap: player.deckMap, score: playerScore});
        }
        game.marketDeckMap = marketDeckMap;
        // call `onFinishGame` hook with players score data.
        IManagerHook(game.gameCreator).onFinishGame(game.hookPermissions, cmd.gameId, playersData, marketDeck);
    }

    /// INTERNAL FUNCTIONS

    /// Checks if core conditions to end the game are met and ends the game if so.
    /// A game will end if:
    ///  - preCondition is true (i.e from a hook).
    ///  - only one player is left in the game.
    ///  - the market deck is empty.
    ///
    /// If the game ends, the market deck is committed.
    function finish(uint256 gameId, GameData storage game, bool preCondition) internal {
        bool playerStoreSingle = game.playerStoreMap.len() == 1;
        bool gameMarketDeckEmpty = game.marketDeckMap.isMapEmpty();
        bool shouldEnd;
        assembly {
            shouldEnd := or(preCondition, or(playerStoreSingle, gameMarketDeckEmpty))
        }
        if (shouldEnd) {
            ensureNoCommittedAction(gameId);
            _commitMarketDeck(gameId, game.marketDeck);
            game.status = GameStatus.Ended;
            emit GameEnded(gameId);
        }
    }

    /// If the forfeiting player is the current player, updates the turn index to the next player.
    /// Calls the `onPlayerExit` hook with `forfeited` set to true.
    function _forfeit(
        uint256 gameId,
        GameData storage game,
        address playerAddr,
        uint256 playerIdx,
        PlayerStoreMap playerStoreMap,
        address gameCreator,
        IRuleset ruleset
    ) internal {
        playerStoreMap = playerStoreMap.removePlayer(playerIdx);
        game.players[playerIdx].forfeited = true;
        // if the forfeiting player is the current player, update the turn index to the next player.
        if (game.playerTurnIdx == playerIdx) {
            game.playerTurnIdx = ruleset.computeNextTurnIndex(playerStoreMap, playerIdx);
            _clearLatestCommittedMove(gameId);
        }
        game.playerStoreMap = playerStoreMap;
        // - call `onPlayerExit` hook.
        IManagerHook(gameCreator).onPlayerExit(game.hookPermissions, gameId, playerAddr, true);
    }

    function _executeMove(
        uint256 gameId,
        GameData storage game,
        address gameCreator,
        HookPermissions hookPermissions,
        IRuleset ruleset,
        IRuleset.ResolveMoveParams memory moveParams
    ) internal {
        uint8 currIdx = moveParams.currentPlayerIndex;
        // clear pending action if any.
        // if a player has a pending action, the ruleset determines whether and how it is resolved.
        if (moveParams.pendingAction != 0) {
            game.players[currIdx].pendingAction = 0;
        }
        // resolve move and get effect.
        IRuleset.Effect memory effect = ruleset.resolveMove(moveParams);
        // apply effect to game state.
        _applyEffect(gameId, game, effect, moveParams);
        PlayerData memory player = game.players[currIdx];

        if (effect.invokeAfterResolveMove) {
            moveParams.playerDeckMap = player.deckMap;
            moveParams.playerHand = player.hand;
            CardEngineLib.grantAccessToHand(moveParams.playerHand, address(ruleset));
            ruleset.afterResolveMove(moveParams);
        }

        if (player.deckMap.isMapEmpty() || effect.currentPlayerExit) {
            moveParams.playerStoreMap = moveParams.playerStoreMap.removePlayer(currIdx);
            // any player that exits the game must not have a pending action. this is expected to be handled by the ruleset.
            if (player.pendingAction != 0) {
                // player cannot exit game with a pending action.
                revert ResolvePendingAction();
            }
            // - call `onPlayerExit` hook.
            IManagerHook(gameCreator).onPlayerExit(hookPermissions, gameId, player.playerAddr, false);
            game.playerStoreMap = moveParams.playerStoreMap;
        }

        emit MoveExecuted(gameId, currIdx, moveParams.gameAction);
    }

    function _applyEffect(
        uint256 gameId,
        GameData storage game,
        IRuleset.Effect memory effect,
        IRuleset.ResolveMoveParams memory moveParams
    ) internal {
        IRuleset.Action[] memory rActions = effect.actions;
        DeckMap marketDeckMap = game.marketDeckMap;

        for (uint256 i = 0; i < rActions.length; i++) {
            // apply effect against player if any.
            if (rActions[i].op.notEqs(IRuleset.EngineOp.None)) {
                uint8 op = uint8(rActions[i].op);
                bool dealPending = op > 8;
                uint8 againstPlayerIdx = rActions[i].againstPlayerIndex;

                // `PendingPick` vs `Pick`: `PendingPick` are `Pick` actions that are not resolved immediately, but must be resolved
                // by the affected player on their turn before they can perform any other action.

                // if `againstPlayerIdx` is not `ALL_OTHER_PLAYERS`, then apply effect against only `againstPlayerIdx`.
                // otherwise, apply effect against all players.
                if (againstPlayerIdx != Constants.ALL_OTHER_PLAYERS) {
                    if (moveParams.playerStoreMap.isEmpty(againstPlayerIdx)) {
                        revert InvalidPlayerIndex();
                    }
                    if (dealPending) {
                        op = op - 8;
                        // if `dealPending` is true, then the against player is dealt the pending pick.
                        game.dealPendingPickN(againstPlayerIdx, op);
                        emit PlayerDealtPending(gameId, againstPlayerIdx, op);
                    } else {
                        // otherwise, the against player is dealt the normal pick.
                        if (op != 1) {
                            marketDeckMap = game.dealPickN(againstPlayerIdx, marketDeckMap, op);
                        } else {
                            marketDeckMap = game.deal(againstPlayerIdx, marketDeckMap);
                        }
                        emit PlayerDealt(gameId, againstPlayerIdx, op);
                    }
                } else {
                    if (dealPending) {
                        op = op - 8;
                        // if `dealPending` is true, then all players are dealt the pending general market pick.
                        game.dealPendingGeneralMarket(moveParams.currentPlayerIndex, op, moveParams.playerStoreMap);
                        emit PlayersDealtGeneralPending(gameId, op);
                    } else {
                        // otherwise, all players are dealt the normal general market pick.
                        marketDeckMap = game.dealGeneralMarket(
                            moveParams.currentPlayerIndex, op, marketDeckMap, moveParams.playerStoreMap
                        );
                        emit PlayersDealtGeneral(gameId, op);
                    }
                }
                game.marketDeckMap = marketDeckMap;
            }
        }

        if (effect.togglePSMDirection) moveParams.playerStoreMap = moveParams.playerStoreMap.toggleDirection();

        // update next player turn index here.
        uint8 nextPlayer = effect.nextPlayerIndex;
        if (moveParams.playerStoreMap.isEmpty(nextPlayer)) {
            revert InvalidPlayerIndex();
        }

        game.playerTurnIdx = nextPlayer;
        game.callCard = effect.callCard;
        game.lastMoveTimestamp = uint40(block.timestamp);
    }

    /// VALIDATION FUNCTIONS

    /// @dev Ensures that the caller is the valid current player in the game.
    function ensureValidCaller(address currentPlayer, uint8 playerIndex, PlayerStoreMap playerStoreMap) internal view {
        if (playerStoreMap.isEmpty(playerIndex)) revert PlayerNotInGame();
        if (currentPlayer != msg.sender) revert InvalidPlayerAddress(msg.sender);
    }

    /// @dev Ensures that the game has started.
    function ensureGameStarted(GameStatus currentStatus) internal pure {
        if (currentStatus.notEqs(GameStatus.Started)) revert GameNotStarted();
    }

    /// @dev Ensures that the current player has not already committed an action.
    function ensureNoCommittedAction(uint256 gameId) internal view {
        if (hasCommittedAction(gameId)) revert PlayerAlreadyCommittedAction();
    }

    /// VIEW FUNCTIONS

    function getPlayerHand(uint256 gameId, uint256 playerIndex) external view returns (DeckMap, euint256[2] memory) {
        PlayerData memory player = gd[gameId].players[playerIndex];
        return (player.deckMap, player.hand);
    }

    function getPlayerData(uint256 gameId, uint256 playerIndex) external view returns (PlayerData memory player) {
        player = gd[gameId].players[playerIndex];
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
        GameData storage game = gd[gameId];

        gameCreator = game.gameCreator;
        callCard = game.callCard;
        playerTurnIdx = game.playerTurnIdx;
        status = game.status;
        lastMoveTimestamp = game.lastMoveTimestamp;
        playersLeftToJoin = game.playersLeftToJoin;
        hookPermissions = game.hookPermissions;
        playerStoreMap = game.playerStoreMap;

        ruleset = game.ruleset;
        marketDeckMap = game.marketDeckMap;
        initialHandSize = game.initialHandSize;
    }
}
