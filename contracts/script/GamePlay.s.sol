// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ICardEngine} from "../src/interfaces/ICardEngine.sol";
import {IRuleset} from "../src/interfaces/IRuleset.sol";
import {WhotManager} from "../src/managers/WhotManager.sol";

contract GamePlay is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint256 p0Key = vm.envUint("PLAYER_0_KEY");
        uint256 p1Key = vm.envUint("PLAYER_1_KEY");
        address cardEngine = vm.envAddress("CARD_ENGINE");
        address managerAddr = vm.envAddress("MANAGER_ADDR");
        address rulesetAddr = vm.envAddress("RULESET_ADDR");
        uint8 maxPlayers = uint8(vm.envUint("WHOT_DEMO_GAME_MAX_PLAYERS"));
        uint8 handSize = uint8(vm.envUint("WHOT_DEMO_GAME_HAND_SIZE"));
        bool roulette = vm.envBool("IS_WHOT_DEMO_GAME_ROULETTE");
        bool suddenDeath = vm.envBool("IS_WHOT_DEMO_GAME_SUDDEN_DEATH");

        address payable p0 = payable(vm.addr(p0Key));
        address payable p1 = payable(vm.addr(p1Key));

        console.log("Player0:", p0);
        console.log("Player1:", p1);
        console.log("Caller:", vm.addr(pk));

        vm.startBroadcast(pk);

        address[] memory empty = new address[](2);
        empty[0] = p0;
        empty[1] = p1;

        uint256 gameId =
            WhotManager(managerAddr).createGame(IRuleset(rulesetAddr), maxPlayers, handSize, empty, roulette, suddenDeath);
        vm.stopBroadcast();

        // Player 0 joins
        vm.startBroadcast(p0Key);
        ICardEngine(cardEngine).joinGame(gameId);
        vm.stopBroadcast();

        // Player 1 joins
        vm.startBroadcast(p1Key);
        ICardEngine(cardEngine).joinGame(gameId);
        vm.stopBroadcast();

        // Start the game (anyone can after all players joined)
        vm.startBroadcast(p0Key);
        ICardEngine(cardEngine).startGame(gameId);
        vm.stopBroadcast();

        console.log("GameId:", gameId);
        console.log("Players joined and game started");
    }
}
