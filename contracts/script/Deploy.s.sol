// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {CardEngine} from "../src/CardEngine.sol";
import {TrustedShuffleServiceV0} from "../src/TrustedShuffleService.sol";

import {ICardEngine} from "../src/interfaces/ICardEngine.sol";
import {WhotRuleset} from "../src/rules/WhotRuleset.sol";

/// @dev Deploys CardEngine, TrustedShuffleServiceV0, and WhotRuleset.
/// Env vars:
/// - PRIVATE_KEY: broadcaster private key
/// - RNG: address of RNG contract for WhotRuleset
/// - TSS_AGENT: address allowed to import shuffle proofs
/// - IMPORTER (optional): address to approve as input-proof importer
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address rng = vm.envOr("RNG", address(0));
        address tssAgent = vm.envAddress("TSS_AGENT");
        address importer = vm.envOr("IMPORTER", address(0));

        vm.startBroadcast(deployerKey);

        CardEngine cardEngine = new CardEngine();
        TrustedShuffleServiceV0 shuffleService = new TrustedShuffleServiceV0(tssAgent);
        WhotRuleset ruleset = new WhotRuleset(rng, ICardEngine(address(cardEngine)));

        if (importer != address(0)) {
            shuffleService.updateImporterApproval(importer, true);
        }

        vm.stopBroadcast();
    }
}
