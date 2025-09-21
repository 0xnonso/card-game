// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {IWhot} from "../interfaces/IWhot.sol";
// import {IWhotManagerHook, IWhotManagerView} from "../interfaces/IWhotManager.sol";
// // import {TournamentData} from "../libraries/TournamentLib.sol";
// import {Action, WhotCard} from "../libraries/WhotLib.sol";

// // import {TrustedShuffleService as TSS} from "./TrustedShuffleService.sol";

// contract WhotLeaderboardV1 is IWhotManagerHook, IWhotManagerView {
//     address public immutable GAME_ADMIN;

//     // TSS internal tss; //tss should implement handSize and cardDeckSize
//     IWhot internal whotGame;
//     // uint256 internal joinWindow;

//     mapping(uint256 tournamentId => TournamentData) tournamentData;
//     mapping(uint256 gameId => uint256 TournamentGameData) tournamentGameData;
//     // mapping(uint256 gameId => TournamentGameData) tournamentGameData;

//     // need to track if a game is a draw rematch, and how many players are to go through.

//     struct TournamentGameData {
//         uint8 rematchData; // bit 0 = is rematch, bits 1-7 = num players to go through
//         uint16 roundId;
//         uint40 startTime;
//         uint192 tournamentId;
//     }

//     struct TournamentData {
//         uint8 currentRound;
//         uint40 startTime;
//         uint16 joinWindow;
//         uint16 settleWindow;
//         uint8 numQualifierRounds;
//         uint8 numPlayersInLobby;
//         address ruleSet; // require the tss.cardBitsSize is supported by ruleSet;
//         mapping(uint256 round => Lobby) lobby;
//         mapping(uint256 round => uint256 finishers) totalFinishers;
//         mapping(uint256 round => uint256 totalScore) totalEffectiveScore;
//         // mapping(uint256 round => mapping(address player => uint16 score)) gameScore;
//         mapping(uint256 round => mapping(address player => int16 score)) effScore;
//         mapping(uint256 round => mapping(address player => bool)) qualifiedForRound;
//     }

//     event WhotGameSet(Iwhot prevWhot, IWhot newWhot);

//     error CallerNotGameAdmin();
//     error CallerNotWhotGame();
//     error RoundInDelayPeriod();

//     modifier onlyGameAdmin() {
//         if (msg.sender != GAME_ADMIN) {
//             revert CallerNotGameAdmin();
//         }
//         _;
//     }

//     modifier onlyWhotGame() {
//         if (msg.sender != address(whotGame)) {
//             revert CallerNotWhotGame();
//         }
//         _;
//     }

//     function setGame(IWhot _whotGame) public onlyGameAdmin {
//         Iwhot prevWhot = whotGame;
//         whotGame = _whotGame;
//         emit WhotGameSet(prevWhot, _whotGame);
//     }

//     function adjustJoinWindow(uint40 newWindow) public onlyGameAdmin {
//         uint40 prevGameJoinWindow = newWindow;
//         joinWindow = newWindow;
//         emit JoinWindowAdjusted(prevGameJoinWindow, newWindow);
//     }

//     // takes a merkle tree root containing all approved participants, and the tournament data.
//     function createWhotTournament(
//         uint40 startTime,
//         uint16 maxDelay,
//         uint8 numRounds,
//         uint24 roundsEpoch,
//         address gameRuleSet
//     ) external onlyGameAdmin {}

//     function resolveGame(uint256 gameId) external {
//         // resolve issues of players not joining and leaving others stranded.
//         // resolve issues of leftover players without teams
//         uint256 tournamentId = gameTournamentId[gameId];
//         TournamentData storage tournament = tournamentData[tournamentId];
//         uint40 joinDeadline = tournamentGameData[gameId].startTime + gameJoinWindow;
//         if (joinDeadline < block.timestamp) {
//             if (whotGame.getNumJoinedPlayers(gameId) > 1) {
//                 whotGame.startGame(gameId);
//             } else {
//                 tournamentGameData[gameId].cancelled = true;

//                 address[] memory players = whotGame.getGamePlayers(gameId);
//                 tournament.lobby.joined[players[0]] = false;
//                 _join(tournamentId, players[0]);
//                 // proceed with effectiveDeduction
//             }
//         }
//     }

//     function join(uint256 tournamentId) external {
//         _join(tournamentId, msg.sender);
//     }

//     function _createNewGame(uint256 tournamentId) internal returns (uint256 gameId) {
//         gameId = whotGame.createGame();
//         gameTournamentId[gameId] = tournamentId;
//     }

//     function _joinTournament(uint256 tournamentId, address player) internal {
//         TournamentData storage tournament = tournamentData[tournamentId];

//         (CacheValue t, uint256 slot) = tournament.toCachedValue();
//         // get current round
//         (uint256 currentRound, bool inSettlePeriod) = getCurrentRound(t.startTime(), t.settleWindow(), t.joinWindow());
//         // check if in delay period
//         if (inDelayPeriod) revert RoundInDelayPeriod();

//         if (t.numPlayersInLobby() == MAX_PLAYERS_IN_LOBBY) {
//             // clear lobby
//             _matchMake(tournamentId, tournament.lobby[currentRound], MAX_PLAYERS_IN_LOBBY);
//             t.updateNumPlayersInLobby(0);
//         }

//         tournament.lobby[currentRound].addPlayer(player, t.numPlayersInLobby());
//     }

//     function _matchMake(uint256 tournamentId, Lobby storage lobby, uint256 numPlayersInLobby, uint256 gameSize)
//         internal
//     {
//         address[] memory lobbyPlayers = lobby.getLobbyPlayers(numPlayersInLobby);
//         bytes32 seed = rng.generatePseudoRandomNumber();
//         FischerYatesShuffle.shuffle(lobbyPlayers, seed);
//         uint256 gamesToCreate = (lobbyPlayers.length + 3) / gameSize;
//         for (uint256 i = 0; i < gamesToCreate; i++) {
//             uint256 gameId = whotGame.createGame();
//             gameTournamentId[gameId] = tournamentId;
//         }
//     }

//     // ideally players should not be able to join agame in delay period as it is intended to round up all existing games.
//     function getCurrentRound(uint40 startTime, uint16 maxDelay, uint24 roundsEpoch)
//         internal
//         view
//         returns (uint256, bool)
//     {
//         uint256 range = block.timestamp - startTime;
//         uint256 maxDelayinSecs = maxDelay * 60;
//         // maybe chck if round is out if range.
//         return (range / ((maxDelayInSecs) + (roundsEpoch * 60)), block.timestamp > (startTime + maxDelayinSecs));
//     }

//     function _handleQualifierRound(
//         TournamentData storage tournament,
//         uint256 roundId,
//         uint256[] calldata playersScoreData
//     ) internal {
//         for (uint256 i = 0; i < playersScoreData.length; i++) {
//             tournament.effScore[roundId][address(uint160(playersScoreData[i]))] =
//                 convertRawToEffScore(playersScoreData[i] >> 160);
//         }
//     }

//     function _handleRematch() internal {}

//     function _handleKORound(
//         TournamentData storage tournament,
//         bool rematch,
//         uint256 roundId,
//         uint256 nextRoundId,
//         uint256[] calldata playersScoreData
//     ) internal {
//         // here calculate score for everybody
//         // only top 2 scores qualify
//         // if there is a tie create roulette game.
//         uint256 scoreDataLen = playersScoreData.length;
//         int256[] memory netEffScoreData = new int256[](scoreDataLen);

//         for (uint256 i = 0; i < scoreDataLen; i++) {
//             uint160 player = uint160(playersScoreData[i]);
//             uint256 effScore = convertRawToEffScore(playersScoreData[i] >> 160);
//             // playersScoreData[i] = (effScore << 160) | uint256(player);
//             tournament.effScore[roundId][address(player)] = effScore;
//             // forgefmt: disable-next-item
//             netEffScoreData[i] = (int256(effScore) + tournament.carryScore[roundId][address(player)]) << 160 | int256(uint256(player));
//         }

//         int256[] memory effScoreOnly = new int256[](scoreDataLen);
//         // Sort score data; returns(sorted_array, duplicates?, array_of_resonable_dups) | then reverse
//         // copy array and isolate score only;
//         // check if array has duplicates.

//         uint256 playersToQualify;
//         address[] memory playersToRematch;

//         if (roundId != nextRoundId) {
//             if (scoreDataLen != 2) {
//                 uint8 duplicateMask;
//                 if (effScoreOnly[1] == effScoreOnly[2]) {
//                     duplicateMask = 0x06;
//                 } else if (effScoreOnly[0] == effScoreOnly[1] == effScoreOnly[2]) {
//                     duplicateMask = 0x07;
//                 }
//                 if (scoreDataLen == 4) {
//                     if (effScoreOnly[1] == effScoreOnly[2] == effScoreOnly[3]) {
//                         duplicateMask = 0x0E;
//                     } else if (effScoreOnly[0] == effScoreOnly[1] == effScoreOnly[2] == effScoreOnly[3]) {
//                         duplicateMask = 0x0F;
//                     }
//                 }

//                 if (duplicateMask != 0) {
//                     uint256 playersLeft = 2;
//                     // handle duplicates
//                     if (duplicateMask & 0x01 == 0) {
//                         // player0 not tied
//                         // address player0 = address(uint160(uint256(netEffScoreData[0])));
//                         // tournament.qualifiedForRound[nextRoundId][player0] = true;
//                         playersToQualify++;
//                         playersLeft--;
//                     }
//                 }
//             } else {
//                 if (effScoreOnly[0] == effScoreOnly[1]) {
//                     playersToRematch = new address[](2);
//                     // create whot game for both with 1 winner.
//                 }
//                 // } else {
//                 //     address player0 = address(uint160(uint256(netEffScoreData[0])));
//                 //     tournament.qualifiedForRound[nextRoundId][player0] = true;
//                 // }
//             }

//             if (playersToRematch.length != 0) {
//                 // create whot game for playersToRematch with `n` winner.
//             }

//             for (uint256 i = 0; i < playersToQualify; i++) {
//                 address player = address(uint160(uint256(netEffScoreData[i])));
//                 tournament.qualifiedForRound[nextRoundId][player] = true;
//             }
//         }
//     }

//     function _handleOnFinishGame(
//         uint256 gameId,
//         uint256 roundId,
//         uint256 tournamentId,
//         uint256[] calldata playersScoreData
//     ) internal {
//         TournamentData storage tournament = tournamentData[tournamentId];
//         (CacheValue t, uint256 slot) = tournament.toCachedValue();

//         if (isRematch) {
//             _handleRematch();
//         } else {
//             if (isQualifierRound) {
//                 _handleQualifierRound(tournament, playersScoreData);
//             } else {
//                 _handleKORound(tournament, playersScoreData);
//             }
//         }
//     }

//     // can have a criteria to own an nft power up to enable superpowers
//     function hasSpecialMoves(uint256 gameId, address player, WhotCard playingCard, Action action)
//         external
//         view
//         virtual
//         override
//         returns (bool)
//     {}

//     function canBootOut(uint256 gameId, address player, uint40 playerLastMoveTimestamp)
//         external
//         view
//         virtual
//         override
//         returns (bool)
//     {}

//     function onJoinGame(uint256 gameId, address player) external virtual override {}

//     function onExecuteMove(uint256 gameId, address player, WhotCard playingCard, Action action)
//         external
//         virtual
//         override
//     {}

//     function onFinishGame(uint256 gameId, uint256[] calldata playersScoreData) external virtual override {
//         // nump​ = (Rmax​+δ−rp​)^γ + K0​⋅1[rp​=0]
//         // nump​ = (Rmax​+δ−rp​)^γ + K0​⋅1[rp​=0]; γ = 2 for finals.
//         // effp​=⌊10,000 ⋅ (nump ​/ ∑q ​numq)​​⌋
//         // if you have more than 1 consecutive forfeits the player is removed.
//         // for qualifiers: average of 2 rounds to enter knock-outs.
//         // LibSort.insertionSort(playersScoreData);

//         TournamentGameData memory gameData = tournamentGameData[gameId];
//         // figure out which round this is.
//         _handleOnFinishGame(gameId, roundId, tournamentId, playersScoreData);
//         (gameId, gameData.roundId, playersScoreData);
//     }

//     function onStartGame(uint256 gameId) external virtual override returns (bool) {}
// }
