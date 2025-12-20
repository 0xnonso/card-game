// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CardEngine} from "../src/CardEngine.sol";
import {TrustedShuffleServiceV0} from "../src/TrustedShuffleService.sol";

import {MinimalRNG} from "../src/helpers/MinimalRNG.sol";
import {ICardEngine} from "../src/interfaces/ICardEngine.sol";
import {WhotCardStandardLibx8} from "../src/libraries/WhotCardDeck.sol";

import {WhotManager} from "../src/managers/WhotManager.sol";
import {WhotRuleset} from "../src/rules/WhotRuleset.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address tssAgent = vm.envAddress("TSS_AGENT");

        console.log("Deploying with deployer", vm.addr(deployerKey));
        console.log("TSS agent", tssAgent);

        vm.startBroadcast(deployerKey);

        MinimalRNG rng = new MinimalRNG();
        CardEngine cardEngine = new CardEngine();
        TrustedShuffleServiceV0 tss = new TrustedShuffleServiceV0(tssAgent, WhotCardStandardLibx8.getDefaultDeck());
        WhotRuleset ruleset = new WhotRuleset(address(rng), ICardEngine(address(cardEngine)));
        WhotManager manager = new WhotManager(ICardEngine(cardEngine), tss);
        tss.updateImporterApproval(address(manager), true);
        tss.updateImporterApproval(vm.addr(deployerKey), true);

        console.log("MinimalRNG deployed at", address(rng));
        console.log("CardEngine deployed at", address(cardEngine));
        console.log("TrustedShuffleServiceV0 deployed at", address(tss));
        console.log("WhotRuleset deployed at", address(ruleset));
        console.log("WhotManager deployed at", address(manager));

        vm.stopBroadcast();
    }
}
