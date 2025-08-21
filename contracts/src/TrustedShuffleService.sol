// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
// import "fhevm/lib/FHE.sol";

// contract TrustedShuffleService {
//     // struct ShuffleData {
//     //     uint256 shuffleRounds;
//     //     euint32[] whotCard;
//     // }
//     address public immutable TSS_AGENT;

//     bytes32[] public shuffledCardDeckRoots;

//     // deckIndex -> amount of input proofs used | mont ashuffledCardDeckRoots array index

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
//     ) public {
//         bytes32 leafHash = keccak256(abi.encode(leaf));
//         bytes32 rootHash = shuffledCardDeckRoots[shuffledCardDeckRootIndex];
//         require(MerkleProof.verify(proof, rootHash, leafHash), "TSS: Invalid merkle root");
//         bytes32 nullifierHash = keccak256(abi.encode(leafHash, rootHash));
//         require(!nullifier[nullifierHash], "TSS: leaf already used");
//         nullifier[nullifierHash] = true;
//     }

//     function updateShuffledCardDeck(bytes32 deckRoot) public onlyTssAgent {
//         shuffledCardDeckRoots.push(deckRoot);
//         emit ShuffledCardDeckRootUpdated(deckRoot);
//     }

//     function updateShuffledCardDeck(bytes[][] memory shuffledCardDeckWithProof)
//         public
//         onlyTssAgent
//     {}

//     function getShuffledCardDeckRoots() public view returns (bytes32[] memory) {
//         return shuffledCardDeckRoots;
//     }

//     function getShuffledCardDeckRootAtIndex(uint256 index) public view returns (bytes32) {
//         return shuffledCardDeckRoots[index];
//     }
// }
