// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IWhot} from "../interfaces/IWhot.sol";
import {IWhotManagerHook, IWhotManagerView} from "../interfaces/IWhotManager.sol";
// import {TournamentData} from "../libraries/TournamentLib.sol";
import {Action, WhotCard} from "../libraries/WhotLib.sol";

// import {TrustedShuffleService as TSS} from "./TrustedShuffleService.sol";

contract WhotLeaderboardV1 is IWhotManagerHook, IWhotManagerView {
    address public immutable GAME_ADMIN;

    // TSS internal tss; //tss should implement handSize and cardDeckSize
    IWhot internal whotGame;
    uint40 internal gameJoinWindow;

    mapping(uint256 tournamentId => TournamentData) tournamentData;
    mapping(uint256 gameId => uint256 tournamentId) gameTournamentId;
    mapping(uint256 gameId => TournamentGameData) tournamentGameData;

    struct TournamentGameData {
        bool cancelled;
        uint40 startTime;
    }

    struct TournamentData {
        uint8 currentRound;
        uint40 startTime;
        uint16 maxDelay;
        uint8 numRounds;
        uint8 numPlayersInLobby;
        uint16 roundsEpoch;
        address ruleSet; // require the tss.cardBitsSize is supported by ruleSet;
        mapping(uint256 round => Lobby) lobby;
        mapping(uint256 round => uint256 finishers) totalFinishers;
        mapping(uint256 round => uint256 totalScore) totalEffectiveScore;
        // mapping(uint256 round => mapping(address player => uint16 score)) gameScore;
        mapping(uint256 round => mapping(address player => int16 score)) effectiveScore;
        mapping(uint256 round => mapping(address player => bool)) qualifiedForRound;
    }

    event WhotGameSet(Iwhot prevWhot, IWhot newWhot);

    error CallerNotGameAdmin();
    error CallerNotWhotGame();
    error RoundInDelayPeriod();

    modifier onlyGameAdmin() {
        if (msg.sender != GAME_ADMIN) {
            revert CallerNotGameAdmin();
        }
        _;
    }

    modifier onlyWhotGame() {
        if (msg.sender != address(whotGame)) {
            revert CallerNotWhotGame();
        }
        _;
    }

    function setGame(IWhot _whotGame) public onlyGameAdmin {
        Iwhot prevWhot = whotGame;
        whotGame = _whotGame;
        emit WhotGameSet(prevWhot, _whotGame);
    }

    function adjustJoinWindow(uint40 newWindow) public onlyGameAdmin {
        uint40 prevGameJoinWindow = newWindow;
        gameJoinWindow = newWindow;
        emit GameJoinWindowAdjusted(prevGameJoinWindow, newWindow);
    }

    // takes a merkle tree root containing all approved participants, and the tournament data.
    function createWhotTournament(
        uint40 startTime,
        uint16 maxDelay,
        uint8 numRounds,
        uint24 roundsEpoch,
        address gameRuleSet
    ) external onlyGameAdmin {}

    function resolveGame(uint256 gameId) external {
        // resolve issues of players not joining and leaving others stranded.
        // resolve issues of leftover players without teams
        uint256 tournamentId = gameTournamentId[gameId];
        TournamentData storage tournament = tournamentData[tournamentId];
        uint40 joinDeadline = tournamentGameData[gameId].startTime + gameJoinWindow;
        if(joinDeadline < block.timestamp){
            if(whotGame.getNumJoinedPlayers(gameId) > 1){
                whotGame.startGame(gameId);
            } else {
                tournamentGameData[gameId].cancelled = true;
                
                address[] memory players = whotGame.getGamePlayers(gameId);
                tournament.lobby.joined[players[0]] = false;
                _join(tournamentId, players[0]);
                // proceed with effectiveDeduction
            }
        }
    }

    function join(uint256 tournamentId) external {
        _join(tournamentId, msg.sender);
    }

    function _joinTournament(uint256 tournamentId, address player) internal {
        TournamentData storage tournament = tournamentData[tournamentId];

        (TournamentCacheValue t, uint256 slot) = tournament.toCachedValue();
        // get current round
        (uint256 currentRound, bool inDelayPeriod) =
            getCurrentRound(t.startTime(), t.maxDelay(), t.roundsEpoch());
        // check if in delay period
        if (inDelayPeriod) revert RoundInDelayPeriod();

        if (t.numPlayersInLobby() == MAX_PLAYERS_IN_LOBBY) {
            // clear lobby
            _matchMake(tournamentId, tournament.lobby[currentRound], MAX_PLAYERS_IN_LOBBY);
            t.updateNumPlayersInLobby(0);
        }

        tournament.lobby[currentRound].addPlayer(player, t.numPlayersInLobby());
    }

    function _matchMake(uint256 tournamentId, Lobby storage lobby, uint256 numPlayersInLobby)
        internal
    {
        address[] memory lobbyPlayers = lobby.getLobbyPlayers(numPlayersInLobby);
        bytes32 seed = rng.generatePseudoRandomNumber();
        FischerYatesShuffle.shuffle(lobbyPlayers, seed);
        uint256 gamesToCreate = (lobbyPlayers.length + 3) / DEFAULT_PLAYERS_IN_GAME;
        for (uint256 i = 0; i < gamesToCreate; i++) {
            uint256 gameId = whotGame.createGame();
            gameTournamentId[gameId] = tournamentId;
        }
    }

    // ideally players should not be able to join agame in delay period as it is intended to round up all existing games.
    function getCurrentRound(uint40 startTime, uint16 maxDelay, uint24 roundsEpoch)
        internal
        view
        returns (uint256, bool)
    {
        uint256 range = block.timestamp - startTime;
        uint256 maxDelayinSecs = maxDelay * 60;
        // maybe chck if round is out if range.
        return (
            range / ((maxDelayInSecs) + (roundsEpoch * 60)),
            block.timestamp > (startTime + maxDelayinSecs)
        );
    }

    // can have a criteria to own an nft power up to enable superpowers
    function hasSpecialMoves(uint256 gameId, address player, WhotCard playingCard, Action action)
        external
        view
        virtual
        override
        returns (bool)
    {}

    function canBootOut(uint256 gameId, address player, uint40 playerLastMoveTimestamp)
        external
        view
        virtual
        override
        returns (bool)
    {}

    function onJoinGame(uint256 gameId, address player) external virtual override {}

    function onExecuteMove(uint256 gameId, address player, WhotCard playingCard, Action action)
        external
        virtual
        override
    {}

    function onFinishGame(uint256 gameId, uint256[] calldata playersScoreData)
        external
        virtual
        override
    {
        // nump​ = (Rmax​+δ−rp​)^γ + K0​⋅1[rp​=0]
        // nump​ = (Rmax​+δ−rp​)^γ + K0​⋅1[rp​=0]; γ = 2 for finals.
        // effp​=⌊10,000 ⋅ (nump ​/ ∑q ​numq)​​⌋
        // if you have more than 1 consecutive forfeits the player is removed.
        // for qualifiers: average of 2 rounds to enter knock-outs.

        uint256 tournamentId = gameTournamentId[gameId];
        uint256 currentRound = 0;
        uint256 playersLen = playersScoreData.length;
        address playerAddr = address(uint160(playerScoreData));
        
        if (playersLen < 5) {
            if (playersLen != 1 || playersLen != 2) {
                // add neg correction the third player.
            } 
        }
        
        for (uint256 i = 0; i < playersLen; i++) {
            if (i > 2) break;
            if(playersLen < 3){
                // add negative deduction here
            }
            tournamentData[tournamentId].qualifiedForRound[nextRound][playerAddr] = true;
        }
    }

    function onStartGame(uint256 gameId) external virtual override returns (bool) {}
}
