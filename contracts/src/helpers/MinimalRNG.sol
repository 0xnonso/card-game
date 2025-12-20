// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRNG} from "../interfaces/IRNG.sol";

contract MinimalRNG is IRNG {
    function generatePseudoRandomNumber() external view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.prevrandao, blockhash(block.number - 1), msg.sender)));
    }

    // !no implementation
    function generateRandomNumber() external view returns (uint256) {}
}
