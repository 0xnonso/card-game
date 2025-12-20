// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/// @notice Simple helper to fund an address for testing on-chain calls.
/// Env:
///   - PRIVATE_KEY: broadcaster key that will send the funds
contract SendFunds is Script {
    function run() external {
        // Load broadcaster key from env.
        uint256 broadcasterKey = vm.envUint("PRIVATE_KEY");
        address payable recipient = payable(0xDf5F958763C3489036329f1E57cF179eb4b5e3c5);
        uint256 amount = 0.04 ether;

        console.log("Sender:", vm.addr(broadcasterKey));
        console.log("Recipient:", recipient);
        console.log("Amount (wei):", amount);

        vm.startBroadcast(broadcasterKey);
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "fund transfer failed");
        vm.stopBroadcast();

        console.log("Transfer complete");
    }
}
