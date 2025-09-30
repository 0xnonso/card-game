// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IRNG} from "../interfaces/IRNG.sol";


contract MockRNG is IRNG {
    uint256 private seed;

    constructor(uint256 _seed) {
        seed = _seed;
    }

    function setSeed(uint256 _seed) external {
        seed = _seed;
    }

    function generatePseudoRandomNumber() external view override returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    seed,
                    blockhash(block.number - 1),
                    block.prevrandao,
                    address(this)
                )
            )
        );
    }

    function generateRandomNumber() external view override returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    seed,
                    blockhash(block.number - 1),
                    block.prevrandao,
                    msg.sender
                )
            )
        );
    }

    function getSeed() external view returns (uint256) {
        return seed;
    }
}