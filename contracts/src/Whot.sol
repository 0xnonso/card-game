// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FHE, euint256, euint8} from "fhevm/lib/FHE.sol";

import {LibSort} from "solady/src/utils/LibSort.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

import {AsyncHandler} from "./base/AsyncHandler.sol";
import {EInputHandler} from "./base/EInputHandler.sol";
import {IRNG} from "./interfaces/IRNG.sol";
import {IWhotManagerHook, IWhotManagerView} from "./interfaces/IWhotManager.sol";

import {ConditionalsLib} from "./libraries/ConditionalsLib.sol";
import {
    Action,
    GameData,
    GameStatus,
    PendingAction,
    PlayerData,
    WhotLib
} from "./libraries/WhotLib.sol";

import {DefaultWhotRuleSet} from "./rules/DefaultWhotRuleSet.sol";
import {GameCacheManager, GameCacheValue} from "./types/Cache.sol";
import {PlayerStoreMap, WhotDeckMap} from "./types/Map.sol";
import {WhotCard, WhotCardLib} from "./types/WhotCard.sol";

import {IRuleSet} from "./interfaces/IRuleSet.sol";

contract Whot is AsyncHandler, EInputHandler, ReentrancyGuard {
    using FHE for *;
    using ConditionalsLib for *;
    using GameCacheManager for GameData;

    uint256 constant MAX_DELAY = 4 minutes;
    // Max number of players in a whot game.
    uint256 constant MAX_PLAYERS_LEN = 8;
    uint256 constant MIN_PLAYERS_LEN = 2;

    IRNG internal rng;
    IRuleSet internal defaultRuleSet;

    // game ID
    uint256 internal whotGameId = 1;

    // Whot Game Data.
    mapping(uint256 gameId => GameData) internal whotGame;

    /// ERRORS
    // Player is  trying to join a game that they already joined.
    error PlayerAlreadyInGame();
    // Caller is trying to join a game that has already started.
    error GameAlreadyStarted();
    // Caller is trying to join a game that has not started yet.
    error GameNotStarted();
    // Can only play or execute move when its player's turn.
    error NotPlayerTurn();
    // Player cannot make any move that doesn't resolve a pending action.
    // i.e If player's pending action is to pick 2, then player can only defend or pick.
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
    error CardSizeNotSupported();

    /// EVENTS
    event PlayerForfeited(uint256 indexed gameId, uint256 playerIndex);
    event PlayerJoined(uint256 indexed gameId, address player);
    event MoveExecuted(uint256 indexed gameId, uint256 pTurnIndex, Action action);
    event PendingActionFulfilled(uint256 indexed gameId, uint256 playerIndex, PendingAction action);
    event GameCreated(uint256 indexed gameId, address gameCreator);
    event GameStarted(uint256 indexed gameId);
    event GameEnded(uint256 indexed gameId);

    constructor(address _ruleSet) AsyncHandler() {
        defaultRuleSet = IRuleSet(_ruleSet);
    }

    // Create a whot game with max number of players.
    // To enable whot manager, caller has to be a smart contract that implements `IWhotManager`
    // If array length greater than zero, then only addresses in the array can join the game.
    // If array is empty, then any participants as much as `maxPlayers` can join the game.
    function createGame(
        EInputData calldata inputData,
        bytes calldata inputProof,
        address[] calldata proposedPlayers,
        IRuleSet gameRuleSet,
        uint256 cardBitSize,
        uint256 cardDeckSize,
        uint8 maxPlayers,
        uint8 initialHandSize
    ) public returns (uint256 gameId) {
        gameId = whotGameId;
        GameData storage game = whotGame[gameId];
        // if ruleSet is empty, set ruleSet to defaultRuleSet.
        game.ruleSet = address(gameRuleSet) != address(0) ? gameRuleSet : defaultRuleSet;
        if (!gameRuleSet.supportsCardSize(cardBitSize)) revert CardSizeNotSupported();

        {
            euint256[2] memory marketDeck = _handleInputData(inputData, inputProof);
            game.marketDeck[0] = marketDeck[0];
            game.marketDeck[1] = marketDeck[1];
            FHE.allowThis(marketDeck[0]);
            FHE.allowThis(marketDeck[1]);
        }

        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        uint8 numProposedPlayers = uint8(proposedPlayers.length);
        maxPlayers = numProposedPlayers != 0 ? numProposedPlayers : maxPlayers;

        if (maxPlayers > MAX_PLAYERS_LEN) revert PlayersLimitExceeded();
        if (maxPlayers < MIN_PLAYERS_LEN) revert PlayersLimitNotMet();

        for (uint256 i = 0; i < numProposedPlayers; i++) {
            game.isProposedPlayer[proposedPlayers[i]] = true;
        }

        game.marketDeckMap = WhotLib.initializeMarketDeckMap(cardDeckSize, cardBitSize);
        PlayerStoreMap playerStoreMap = WhotLib.initializePlayerStoreMap(numProposedPlayers);

        g = g.updatePlayerStoreMap(playerStoreMap);
        g = g.updateMaxPlayers(maxPlayers);
        g = g.updatePlayersLeftToJoin(maxPlayers);
        g = g.updateGameCreator(msg.sender);
        g = g.updateHandSize(initialHandSize);
        g.toStorage(slot);

        unchecked {
            whotGameId++;
        }

        emit GameCreated(gameId, msg.sender);
    }

    /// @notice Allows a player to join a Whot game if the game hasn’t started yet.
    /// @dev A player can only join the game if they’re on the proposed players list (which must be set)
    ///      or if the maximum player limit hasn’t been reached.
    function joinGame(uint256 gameId) public nonReentrant {
        GameData storage game = whotGame[gameId];
        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        if (g.status().not_eqs(GameStatus.None)) revert GameAlreadyStarted();

        address playerToAdd = msg.sender;
        PlayerStoreMap playerStoreMap = g.playerStoreMap();
        uint8 playersLeftToJoin = g.playersLeftToJoin();

        // use player store map to check if player is already in game.
        if (game.isPlayerActive(playerToAdd, playerStoreMap)) revert PlayerAlreadyInGame();

        // if player is not a proposed player, then check if max players limit has been reached.
        // if proposed players is set (i.e proposed players array > 0), then check if player is in the proposed players list.
        bool isProposedPlayer = playerStoreMap.getNumProposedPlayers() != 0
            ? game.isProposedPlayer[playerToAdd]
            : playersLeftToJoin != 0;

        if (isProposedPlayer) {
            playerStoreMap = game.addPlayer(playerToAdd, playerStoreMap);
            playersLeftToJoin--;
            g = g.updatePlayersLeftToJoin(playersLeftToJoin);
            g = g.updatePlayerStoreMap(playerStoreMap);
            g.toStorage(slot);
        } else {
            revert NotProposedPlayer(playerToAdd);
        }

        bytes memory payload =
            abi.encodeWithSelector(IWhotManagerHook.onJoinGame.selector, gameId, playerToAdd);
        g.gameCreator().call(payload);

        emit PlayerJoined(gameId, playerToAdd);
    }

    /// Start a whot game.
    function startGame(uint256 gameId) external {
        GameData storage game = whotGame[gameId];
        PlayerData[] memory players = game.players;

        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        uint256 playersLeftToJoin = g.playersLeftToJoin();
        uint256 joined = g.maxPlayers() - playersLeftToJoin;
        address gameCreator = g.gameCreator();

        // can only start game if:
        //  i. `playersLeftToJoin` is zero (i.e all players have joined).
        //  ii. game creator is the caller and at least 2 players have joined.
        bool canStartGame;
        assembly ("memory-safe") {
            // forgefmt: disable-next-item
            canStartGame := or(iszero(playersLeftToJoin), and(eq(caller(), gameCreator), gt(joined, 0x01)))
        }

        // if game can start, all players are dealt an initial hand, and the score is set to the minimum value of type(uint16).max (65,535).
        if (canStartGame) {
            for (uint256 i = 0; i < players.length; i++) {
                PlayerData memory player = players[i];
                game.setPlayerScoreToMin(i);
                game.dealInitialHand(player, i, joined, g.initialHandSize());
            }
        } else {
            revert CannotStartGame();
        }

        g = g.updateStatus(GameStatus.Started);
        g = g.updatePlayerTurnIndex(game.ruleSet.computeStartIndex(g.playerStoreMap()));
        g.toStorage(slot);

        emit GameStarted(gameId);

        // need to allocate max gas to be used in hook callback.
        bytes memory payload = abi.encodeWithSelector(IWhotManagerHook.onStartGame.selector, gameId);
        (bool success, bytes memory returnData) = gameCreator.call(payload);
        if (success) {
            bool end = abi.decode(returnData, (bool));
            // `playerId` is irrelevant here; we force-finish by zeroing PlayerStoreMap.
            if (end) finish(gameId, game, 0, PlayerStoreMap.wrap(0));
        }
    }

    function commitMove(uint256 gameId, Action action, uint256 cardIndex, bytes memory extraData)
        external
    {
        ensureNoCommittedAction(gameId);

        GameData storage game = whotGame[gameId];
        (GameCacheValue g,) = game.toCachedValue();

        ensureGameStarted(g.status());

        uint256 currentTurnIndex = g.playerTurnIndex();
        PlayerData memory player = game.players[currentTurnIndex];

        ensurePlayerTurn(player.playerAddr);

        if (!action.eqs_or(Action.Play, Action.Defend)) {
            revert InvalidGameAction(action);
        }

        euint8 cardToCommit = game.getCardToCommit(player, cardIndex);
        WhotDeckMap updatedPlayerDeckMap = player.emptyDeckMapAtIndex(cardIndex);

        _commitMove(gameId, cardToCommit, action, updatedPlayerDeckMap, currentTurnIndex, extraData);
    }

    // Execute player's move.
    function executeMove(uint256 gameId, Action action) external nonReentrant {
        GameData storage game = whotGame[gameId];
        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        ensureGameStarted(g.status());

        uint8 playerTurnIdx = g.playerTurnIndex();
        address playerAddr = game.players[playerTurnIdx].playerAddr;

        ensurePlayerTurn(playerAddr);
        ensureNoCommittedAction(gameId);

        if (!action.eqs_or(Action.GoToMarket, Action.Pick)) {
            revert InvalidGameAction(action);
        }

        goToMarketOrPick(gameId, game, action, playerTurnIdx, g, slot);

        // WhotCard(0xff) represents an invaild or empty whot card.
        bytes memory payload = abi.encodeWithSelector(
            IWhotManagerHook.onExecuteMove.selector,
            gameId,
            playerAddr,
            WhotCardLib.toWhotCard(0xff),
            action
        );
        g.gameCreator().call(payload);

        finish(gameId, game, playerTurnIdx, g.playerStoreMap());
    }

    function handleCommitMove(uint256 requestId, uint8 rawCard, bytes[] memory signatures)
        external
        virtual
        override
    {
        CommittedCard memory cc = getCommittedMove(requestId);
        __validateCallbackSignature(requestId, cc.gameId, signatures);
        GameData storage game = whotGame[cc.gameId];
        WhotCard whotCard = WhotCardLib.toWhotCard(rawCard);
        game.players[cc.playerIndex].deckMap = cc.updatedPlayerDeckMap;

        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        playOrDefend(cc.gameId, game, cc.action, whotCard, g, slot, cc.extraData);

        bytes memory payload = abi.encodeWithSelector(
            IWhotManagerHook.onExecuteMove.selector,
            cc.gameId,
            game.players[cc.playerIndex].playerAddr,
            whotCard,
            cc.action
        );
        g.gameCreator().call(payload);

        clearCommitment(cc.gameId, requestId);
        finish(cc.gameId, game, cc.playerIndex, g.playerStoreMap());
    }

    function handleCommitMarketDeck(
        uint256 requestId,
        uint256[2] memory marketDeck,
        bytes[] memory signatures
    ) external virtual override nonReentrant {
        CommittedMarketDeck memory cmd = getCommittedMarketDeck(requestId);
        __validateCallbackSignature(requestId, cmd.gameId, signatures);
        GameData storage game = whotGame[cmd.gameId];
        PlayerData[] storage players = game.players;
        // get only active players.
        PlayerStoreMap playerStoreMap = game.playerStoreMap;
        uint256[] memory playerIndexes = playerStoreMap.getNonEmptyIdxs();

        for (uint256 i = 0; i < playerIndexes.length; i++) {
            game.calculateAndSetPlayerScore(playerIndexes[i], marketDeck);
        }

        uint256[] memory playersScoreData = new uint256[](playerStoreMap.len());
        for (uint256 i = 0; i < playersScoreData.length; i++) {
            assembly ("memory-safe") {
                let playerSlot := players.slot
                let slotValue := sload(playerSlot)
                // get [score, address] value and set `playersScoreData[i] = value`
            }
        }
        LibSort.insertionSort(playersScoreData);
        bytes memory payload = abi.encodeWithSelector(
            IWhotManagerHook.onFinishGame.selector, cmd.gameId, playersScoreData
        );
        game.gameCreator.call(payload);
    }

    /// Fails silently. Might be an anti patern? Todo(nonso): fix?
    function finish(
        uint256 gameId,
        GameData storage game,
        uint256 currentPlayerIdx,
        PlayerStoreMap playerStoreMap
    ) internal {
        PlayerData memory player = game.players[currentPlayerIdx];

        bool playerStoreEmpty = playerStoreMap.isMapEmpty();
        bool gameMarketDeckEmpty = game.marketDeckMap.isMapEmpty();
        bool playerDeckEmpty = player.deckMap.isMapEmpty();

        // game can end if:
        //  i. game market deck is empty
        //  ii. player deck is empty
        //  iii. only one player is active
        //  iv. force is true (i.e game manager is forcing the game to end)
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

    // Forfeit whot game.
    function forfeit(uint256 gameId) external {
        GameData storage game = whotGame[gameId];

        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        ensureGameStarted(g.status());

        uint256 playerIdx = game.getPlayerIndex(msg.sender);
        PlayerStoreMap _map = _forfeit(gameId, game, playerIdx, g, slot);
        finish(gameId, game, playerIdx, _map);
    }

    // Remove player from game.
    function bootOut(uint256 gameId) external {
        GameData storage game = whotGame[gameId];
        (GameCacheValue g, uint256 slot) = game.toCachedValue();

        ensureGameStarted(g.status());

        uint256 turnIdx = g.playerTurnIndex();
        address player = game.players[turnIdx].playerAddr;
        uint40 lastMoveTimestamp = g.lastMoveTimestamp();

        bytes memory payload = abi.encodeWithSelector(
            IWhotManagerView.canBootOut.selector, gameId, player, lastMoveTimestamp
        );
        (bool success, bytes memory returnData) = g.gameCreator().call(payload);
        bool canBootOut = success
            ? abi.decode(returnData, (bool))
            : (lastMoveTimestamp + MAX_DELAY) <= block.timestamp;

        if (!canBootOut) revert CannotBootOutPlayer(player);

        PlayerStoreMap playersMap = _forfeit(gameId, game, turnIdx, g, slot);
        finish(gameId, game, turnIdx, playersMap);
    }

    function _forfeit(
        uint256 gameId,
        GameData storage game,
        uint256 playerIdx,
        GameCacheValue g,
        uint256 slot
    ) internal returns (PlayerStoreMap newPlayerStoreMap) {
        g = g.updatePlayerStoreMap(g.playerStoreMap().removePlayer(playerIdx));
        newPlayerStoreMap = g.playerStoreMap();
        if (g.playerTurnIndex() == playerIdx) {
            g = g.updatePlayerTurnIndex(
                game.ruleSet.computeNextTurnIndex(newPlayerStoreMap, playerIdx)
            );
        }
        g.toStorage(slot);

        emit PlayerForfeited(gameId, playerIdx);
    }

    // Play whot card.
    function playOrDefend(
        uint256 gameId,
        GameData storage game,
        Action action,
        WhotCard card,
        GameCacheValue g,
        uint256 slot,
        bytes memory extraData
    ) internal {
        uint8 currentIdx = g.playerTurnIndex();

        PlayerData memory player = game.players[currentIdx];
        PendingAction pendingAction = player.pendingAction;

        // clear pending action if any.
        if (pendingAction.not_eqs(PendingAction.None)) {
            game.players[currentIdx].pendingAction = PendingAction.None;
        }

        IRuleSet ruleSet = game.ruleSet;

        bool isEligibleForSpecialMove;
        if (ruleSet.isSpecialMoveCard(card)) {
            bytes memory payload = abi.encodeWithSelector(
                IWhotManagerView.hasSpecialMoves.selector, gameId, player.playerAddr, card, action
            );
            (bool success, bytes memory returnData) = g.gameCreator().call(payload);
            if (success) isEligibleForSpecialMove = abi.decode(returnData, (bool));
        }

        PlayerStoreMap playerStoreMap = g.playerStoreMap();

        IRuleSet.MoveValidationResult memory res = ruleSet.validateMove(
            IRuleSet.MoveValidationParams({
                gameAction: action,
                pendingAction: pendingAction,
                card: card,
                callCard: g.callCard(),
                cardSize: game.marketDeckMap.getDeckCardSize(),
                currentPlayerIndex: currentIdx,
                playerStoreMap: playerStoreMap,
                isSpecial: isEligibleForSpecialMove,
                extraData: extraData
            })
        );

        _executeRuleSetMoveResult(game, res, playerStoreMap);

        // update player turn index here.
        g = g.updatePlayerTurnIndex(res.nextPlayerIndex);
        g = g.updateCallCard(res.callCard);
        g = g.updateLastMoveTimestamp(uint40(block.timestamp));
        g.toStorage(slot);

        emit MoveExecuted(gameId, currentIdx, action);
    }

    // pick 2, pick 4
    function goToMarketOrPick(
        uint256 gameId,
        GameData storage game,
        Action action,
        uint256 currentIndex,
        GameCacheValue g,
        uint256 slot
    ) internal {
        PlayerData memory player = game.players[currentIndex];

        if (action.eqs(Action.GoToMarket)) {
            if (player.pendingAction.not_eqs(PendingAction.None)) {
                revert ResolvePendingAction();
            }
            game.deal(player, currentIndex);
        } else {
            if (player.pendingAction.eqs(PendingAction.None)) {
                revert NoPendingAction();
            }
            game.dealPickN(player, currentIndex, uint8(player.pendingAction));
            // clear pending action.
            game.players[currentIndex].pendingAction = PendingAction.None;
            emit PendingActionFulfilled(gameId, currentIndex, player.pendingAction);
        }

        uint8 nextIdx = game.ruleSet.computeNextTurnIndex(g.playerStoreMap(), currentIndex);
        // update player turn index here.
        g = g.updatePlayerTurnIndex(nextIdx);
        g = g.updateLastMoveTimestamp(uint40(block.timestamp));
        g.toStorage(slot);

        emit MoveExecuted(gameId, currentIndex, Action.Pick);
    }

    function _executeRuleSetMoveResult(
        GameData storage game,
        IRuleSet.MoveValidationResult memory res,
        PlayerStoreMap playerStoreMap
    ) internal {
        IRuleSet.Action actionToExec = res.action;
        if (actionToExec.not_eqs(IRuleSet.Action.None)) {
            uint8 action = uint8(res.action);
            bool dealPending = action > 8;
            uint8 againstPlayerIdx = res.againstPlayerIndex;

            if (playerStoreMap.isEmpty(againstPlayerIdx)) {
                revert InvalidPlayerIndex();
            }

            if (againstPlayerIdx != type(uint8).max) {
                if (dealPending) {
                    game.dealPendingPickN(againstPlayerIdx, action - 8);
                } else {
                    PlayerData memory againstPlayer = game.players[againstPlayerIdx];
                    game.dealPickN(againstPlayer, againstPlayerIdx, action);
                }
            } else {
                if (dealPending) {
                    game.dealPendingGeneralMarket(againstPlayerIdx, action - 8, playerStoreMap);
                } else {
                    game.dealGeneralMarket(againstPlayerIdx, action, playerStoreMap);
                }
            }
        }
    }

    function getPlayerWhotCardDeck(uint256 gameId, uint256 playerIndex)
        public
        view
        returns (WhotDeckMap, euint256[2] memory)
    {
        PlayerData memory player = whotGame[gameId].players[playerIndex];
        return (player.deckMap, player.whotCardDeck);
    }

    function ensurePlayerTurn(address currentPlayer) private view {
        if (currentPlayer != msg.sender) revert NotPlayerTurn();
    }

    function ensureGameStarted(GameStatus currentStatus) private pure {
        if (currentStatus.not_eqs(GameStatus.Started)) revert GameNotStarted();
    }

    function ensureNoCommittedAction(uint256 gameId) private view {
        if (hasCommittedAction(gameId)) revert PlayerAlreadyCommittedAction();
    }

    function getPlayerData(uint256 gameId, uint256 playerIndex)
        external
        view
        returns (PlayerData memory)
    {
        return whotGame[gameId].players[playerIndex];
    }

    function getGameStatus(uint256 gameId) external view returns (GameStatus) {
        return whotGame[gameId].status;
    }

    function gameNotStarted(uint256 gameId) external view returns (bool) {
        return whotGame[gameId].status == GameStatus.None;
    }

    function getNumJoinedPlayers(uint256 gameId) external view returns (bool) {
        return whotGame[gameId].playerStoreMap.len();
    }
}
