// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IRNG {
    function generatePseudoRandomNumber() external returns (uint256);
    function genrateRandomNumber() external returns (uint256);
}
