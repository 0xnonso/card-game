// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SepoliaConfig} from "fhevm/config/ZamaConfig.sol";
import {FHE, euint256, euint8} from "fhevm/lib/FHE.sol";

import {Action} from "../libraries/WhotLib.sol";
import {WhotDeckMap} from "../types/Map.sol";

abstract contract AsyncHandler is SepoliaConfig {
    using FHE for *;

    // uint256 immutable MAX_CALLBACK_DELAY;

    mapping(uint256 requestId => CommittedCard) private requestToCommittedMove;
    // mapping(uint256 gameId => uint256 requestId) private committedMoveToGatewayRequest;
    mapping(uint256 requestId => CommittedMarketDeck) private requestToCommittedMarketDeck;
    mapping(uint256 gameId => mapping(uint256 req => bool)) private _isLatestRequest;
    mapping(uint256 gameId => bool) private _hasCommittedAction;

    struct CommittedCard {
        Action action;
        uint40 timestamp;
        uint8 playerIndex;
        WhotDeckMap updatedPlayerDeckMap;
        euint8 card;
        uint256 gameId;
        bytes extraData;
    }

    struct CommittedMarketDeck {
        uint256 gameId;
        euint256[2] marketDeck;
    }

    constructor() {}

    function _commitMove(
        uint256 gameId,
        euint8 cardToCommit,
        Action action,
        WhotDeckMap updatedPlayerDeckMap,
        uint256 playerIndex,
        bytes memory extraData
    ) internal {
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(cardToCommit);

        uint256 reqId = FHE.requestDecryption(cts, this.handleCommitMove.selector);

        CommittedCard memory cc = CommittedCard({
            action: action,
            timestamp: uint40(block.timestamp),
            playerIndex: uint8(playerIndex),
            updatedPlayerDeckMap: updatedPlayerDeckMap,
            card: cardToCommit,
            gameId: gameId,
            extraData: extraData
        });

        _hasCommittedAction[gameId] = true;
        _isLatestRequest[gameId][reqId] = true;
        requestToCommittedMove[reqId] = cc;
        // committedMoveToGatewayRequest[gameId] = reqId;
    }

    function _commitMarketDeck(uint256 gameId, euint256[2] memory marketDeck) internal {
        bytes32[] memory cts = new bytes32[](2);
        cts[0] = FHE.toBytes32(marketDeck[0]);
        cts[1] = FHE.toBytes32(marketDeck[1]);

        uint256 reqId = FHE.requestDecryption(cts, this.handleCommitMarketDeck.selector);

        CommittedMarketDeck memory committedMarketDeck =
            CommittedMarketDeck({gameId: gameId, marketDeck: marketDeck});
        // committedMarketDeck.gameId = gameId;
        // committedMarketDeck.playerIndexes = playerIndexes;
        _hasCommittedAction[gameId] = true;
        _isLatestRequest[gameId][reqId] = true;
        requestToCommittedMarketDeck[reqId] = committedMarketDeck;
    }

    function __validateCallbackSignature(uint256 reqId, uint256 gameId, bytes[] memory signatures)
        internal
    {
        if (!_isLatestRequest[gameId][reqId]) revert();
        FHE.checkSignatures(reqId, signatures);
    }

    function getCommittedMove(uint256 reqId) internal view returns (CommittedCard memory) {
        return requestToCommittedMove[reqId];
    }

    function getCommittedMarketDeck(uint256 reqId)
        internal
        view
        returns (CommittedMarketDeck memory)
    {
        return requestToCommittedMarketDeck[reqId];
    }

    function hasCommittedAction(uint256 gameId) internal view returns (bool) {
        // return committedMoveToGatewayRequest[gameId] != 0;
        return _hasCommittedAction[gameId];
    }

    function clearCommitment(uint256 gameId, uint256 reqId) internal {
        // committedMoveToGatewayRequest[gameId] = 0;
        _hasCommittedAction[gameId] = false;
        _isLatestRequest[gameId][reqId] = false;
    }

    function isLatestRequest(uint256 gameId, uint256 reqId) internal view returns (bool) {
        return _isLatestRequest[gameId][reqId];
    }

    function handleCommitMove(uint256 requestId, uint8 card, bytes[] memory signatures)
        external
        virtual;
    function handleCommitMarketDeck(
        uint256 requestId,
        uint256[2] memory marketDeck,
        bytes[] memory signatures
    ) external virtual;
}
