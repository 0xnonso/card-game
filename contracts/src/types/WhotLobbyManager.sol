// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

uint256 constant MAX_PLAYERS_IN_LOBBY = 16;

struct Lobby {
    // issues: need to pick the players randomly to try and prevent collusion.
    // reduce the number of players per game to 4. not 6.
    //
    // length of players array,
    // number of players in lobby,
    // uint8 numPlayers;
    // uint16 lobbyMap;
    address[MAX_PLAYERS_IN_LOBBY] players;
    mapping(address => bool) joined;
}

using LobbyManager for Lobby global;

library LobbyManager {
    // function setUpLobby(Lobby storage lobby, Tournament memory tournamentData) internal {}

    // error LobbyManager__PlayerJoined();
    // error LobbyManager__LobbyAtMaxCapacity();

    error PlayerAlreadyJoined(address);

    function addPlayer(Lobby storage lobby, address player, uint256 index) internal {
        if (lobby.joined[player]) revert PlayerAlreadyJoined(player);
        lobby.players[index] = player;
    }

    function reset(Lobby storage lobby, uint256 prevNumPlayers) internal {
        for (uint256 i = 0; i < prevNumPlayers; i++) {
            delete lobby.players[i];
        }
    }

    function getLobbyPlayers(Lobby storage lobby, uint256 numPlayers) internal view returns (address[] memory) {
        address[] memory lobbyPlayers = new address[](numPlayers);
        for (uint256 i = 0; i < numPlayers; i++) {
            lobbyPlayers[i] = lobby.players[i];
        }
        return lobbyPlayers;
    }
}
