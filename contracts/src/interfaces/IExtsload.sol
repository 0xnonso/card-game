// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IExtsload {
    function extsload(uint256 slot) external view returns (uint256);
    function extsload(uint256 startSlot, uint256 nSlots) external view returns (uint256[] memory values);
    function extsload(uint256[] calldata slots) external view returns (uint256[] memory values);
}
