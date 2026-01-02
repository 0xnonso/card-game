// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FHE, euint256, euint8} from "@fhevm/solidity/lib/FHE.sol";

abstract contract AsyncHandler {
    mapping(uint256 gameId => bytes32) private commitment;

    error AsyncHandler_InvalidCommitmentHash();

    event MoveCommitted(uint256 indexed gameId, euint8 cardToCommit, uint256 cardIndex);
    event MarketDeckCommitted(uint256 indexed gameId, euint256[2] marketDeck);
    event ClearCommitment(uint256 indexed gameId);

    function __validateMoveDecryption(uint256 gameId, bytes memory proof)
        internal
        returns (bytes memory decryptionProof, euint8 encryptedCard, bytes memory decryptionResult, uint8 cardIndex)
    {
        // decryption proof, encrypted card, decryption result, cardIndex
        (decryptionProof, encryptedCard, decryptionResult, cardIndex) = abi.decode(proof, (bytes, euint8, bytes, uint8));
        _validateHash(gameId, _hash(abi.encode(encryptedCard, cardIndex)));
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(encryptedCard);
        FHE.checkSignatures(cts, decryptionResult, decryptionProof);
    }

    function __validateMarketDeckDecryption(uint256 gameId, bytes memory proof)
        internal
        returns (bytes memory decryptionProof, euint256[2] memory encryptedDeck, bytes memory decryptionResult)
    {
        // decryption proof, encrypted deck, decryption result
        (decryptionProof, encryptedDeck, decryptionResult) = abi.decode(proof, (bytes, euint256[2], bytes));
        _validateHash(gameId, _hash(abi.encode(encryptedDeck)));
        bytes32[] memory cts = new bytes32[](2);
        cts[0] = FHE.toBytes32(encryptedDeck[0]);
        cts[1] = FHE.toBytes32(encryptedDeck[1]);
        FHE.checkSignatures(cts, decryptionResult, decryptionProof);
    }

    function _validateHash(uint256 gameId, bytes32 _hash_) internal view {
        if (commitment[gameId] != _hash_) {
            revert AsyncHandler_InvalidCommitmentHash();
        }
    }

    function _commitMove(uint256 gameId, euint8 cardToCommit, uint256 cardIndex) internal {
        FHE.makePubliclyDecryptable(cardToCommit);
        commitment[gameId] = _hash(abi.encode(cardToCommit, cardIndex));

        emit MoveCommitted(gameId, cardToCommit, cardIndex);
    }

    function _commitMarketDeck(uint256 gameId, euint256[2] memory marketDeck) internal {
        FHE.makePubliclyDecryptable(marketDeck[0]);
        FHE.makePubliclyDecryptable(marketDeck[1]);
        commitment[gameId] = _hash(abi.encode(marketDeck));

        emit MarketDeckCommitted(gameId, marketDeck);
    }

    function _clearCommitment(uint256 gameId) internal {
        delete commitment[gameId];

        emit ClearCommitment(gameId);
    }

    function _hasCommittedAction(uint256 gameId) internal view returns (bool) {
        return commitment[gameId] != 0;
    }

    function _hash(bytes memory encodedData) internal pure returns (bytes32) {
        return keccak256(encodedData);
    }
}
