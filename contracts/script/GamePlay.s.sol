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

        address payable p0 = payable(vm.addr(p0Key));
        address payable p1 = payable(vm.addr(p1Key));

        address managerAddr = 0x7066Ec9d108d3c6F45d50f53EbBeE1188d058BbB;
        address rulesetAddr = 0x02707bBB7229721e841Ebeecb95943eef340b2Be;

        console.log("Player0:", p0);
        console.log("Player1:", p1);
        console.log("CardEngine:", cardEngine);
        console.log("Caller:", vm.addr(pk));
        console.log("WhotManager:", managerAddr);
        console.log("Ruleset:", rulesetAddr);

        vm.startBroadcast(pk);

        address[] memory empty = new address[](2);
        empty[0] = p0;
        empty[1] = p1;
        uint8 maxPlayers = 2;
        uint8 handSize = 5;
        bool roulette = true;
        uint256 gameId =
            WhotManager(managerAddr).createGame(IRuleset(rulesetAddr), maxPlayers, handSize, empty, roulette);
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
