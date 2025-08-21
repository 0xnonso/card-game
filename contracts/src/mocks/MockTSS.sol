// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
// import "fhevm/lib/FHE.sol";

// contract MockTrustedShuffleService {
//     address public immutable TSS_AGENT;

//     bytes32[] public shuffledCardDeckRoots;

//     mapping(bytes32 nullifierHash => bool) internal nullifier;

//     event ShuffledCardDeckRootUpdated(bytes32 deckRoot);

//     modifier onlyTssAgent() {
//         require(msg.sender == TSS_AGENT, "TSS: Only TSS Agent can call this function");
//         _;
//     }

//     constructor(address _tssAgent) {
//         TSS_AGENT = _tssAgent;
//     }

//     function verifyAndUseShuffledCardDeck(
//         bytes32[] memory proof,
//         einput[2] memory leaf,
//         uint256 shuffledCardDeckRootIndex
//     ) public {}

//     function updateShuffledCardDeck(bytes32 deckRoot) public {
//         shuffledCardDeckRoots.push(deckRoot);
//         emit ShuffledCardDeckRootUpdated(deckRoot);
//     }

//     function getShuffledCardDeckRoots() public view returns (bytes32[] memory) {
//         return shuffledCardDeckRoots;
//     }

//     function getShuffledCardDeckRootAtIndex(uint256 index) public view returns (bytes32) {
//         return shuffledCardDeckRoots[index];
//     }
// }
