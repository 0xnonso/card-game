// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IRNG {
    function generatePseudoRandomNumber() external view returns (uint256);
    function genrateRandomNumber() external view returns (uint256);
}
