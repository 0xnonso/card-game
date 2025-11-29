// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import {SepoliaConfig} from "fhevm/config/ZamaConfig.sol";
import {FHE, euint256, euint8} from "@fhevm/solidity/lib/FHE.sol";

import {Action} from "../libraries/CardEngineLib.sol";
import {Card, CardLib} from "../types/Card.sol";
import {DeckMap} from "../types/Map.sol";

abstract contract AsyncHandler {
    using FHE for *;

    uint256 constant DEFAULT_REQUEST_ID = type(uint256).max;
    uint256 private _latestRequest;

    mapping(uint256 requestId => CommittedMoveData) private requestToCommittedMove;
    mapping(uint256 requestId => CommittedMarketDeck) private requestToCommittedMarketDeck;

    mapping(uint256 gameId => uint256) private gameIdToLatestCommittedMoveRequestId;
    mapping(uint256 gameId => uint256) private gameIdToLatestCommittedMarketDeckRequestId;
    mapping(uint256 gameId => bool) private _hasCommittedAction;

    struct CommittedMoveData {
        uint256 gameId;
        Action action;
        uint8 cardIndex;
        uint8 playerIndex;
        Card decryptedCard;
        bool fulfilled;
    }

    struct CommittedMarketDeck {
        uint256 gameId;
        euint256[2] marketDeck;
    }

    function _initializeEngineCallback(uint256 gameId) internal {
        gameIdToLatestCommittedMoveRequestId[gameId] = DEFAULT_REQUEST_ID;
        gameIdToLatestCommittedMarketDeckRequestId[gameId] = DEFAULT_REQUEST_ID;
    }

    function _commitMove(uint256 gameId, euint8 cardToCommit, Action action, uint256 cardIndex, uint256 playerIndex)
        internal
    {
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(cardToCommit);

        uint256 reqId = FHE.requestDecryption(cts, this.handleCommitMove.selector);

        CommittedMoveData memory committedMove = CommittedMoveData({
            gameId: gameId,
            action: action,
            cardIndex: uint8(cardIndex),
            playerIndex: uint8(playerIndex),
            fulfilled: false,
            decryptedCard: CardLib.toCard(0)
        });

        gameIdToLatestCommittedMoveRequestId[gameId] = reqId;
        requestToCommittedMove[reqId] = committedMove;
        _hasCommittedAction[gameId] = true;
    }

    function _commitMarketDeck(uint256 gameId, euint256[2] memory marketDeck) internal {
        bytes32[] memory cts = new bytes32[](2);
        cts[0] = FHE.toBytes32(marketDeck[0]);
        cts[1] = FHE.toBytes32(marketDeck[1]);

        uint256 reqId = FHE.requestDecryption(cts, this.handleCommitMarketDeck.selector);

        FHE.makePubliclyDecryptable(marketDeck[0]);
        FHE.makePubliclyDecryptable(marketDeck[1]);

        CommittedMarketDeck memory committedMarketDeck = CommittedMarketDeck({gameId: gameId, marketDeck: marketDeck});

        gameIdToLatestCommittedMarketDeckRequestId[gameId] = reqId;
        requestToCommittedMarketDeck[reqId] = committedMarketDeck;
        _hasCommittedAction[gameId] = true;
    }

    function __validateCallbackSignature(
        uint256 reqId,
        bytes memory clearTexts,
        uint256 gameId,
        bytes memory decryptionProof,
        bool isCommittedMoveAction
    ) internal {
        if (isCommittedMoveAction) {
            require(
                gameIdToLatestCommittedMoveRequestId[gameId] == reqId && reqId != DEFAULT_REQUEST_ID,
                "AsyncHandler: not latest committed move request"
            );
        } else {
            require(
                gameIdToLatestCommittedMarketDeckRequestId[gameId] == reqId && reqId != DEFAULT_REQUEST_ID,
                "AsyncHandler: not latest committed market deck request"
            );
        }
        FHE.checkSignatures(reqId, clearTexts, decryptionProof);
    }

    function getCommittedMarketDeck(uint256 reqId) internal view returns (CommittedMarketDeck memory) {
        return requestToCommittedMarketDeck[reqId];
    }

    function getCommittedMove(uint256 reqId) internal view returns (CommittedMoveData memory) {
        return requestToCommittedMove[reqId];
    }

    function getLatestCommittedMove(uint256 gameId) internal view returns (CommittedMoveData memory) {
        uint256 latestReqId = gameIdToLatestCommittedMoveRequestId[gameId];
        CommittedMoveData memory committedMove = requestToCommittedMove[latestReqId];
        if (latestReqId != DEFAULT_REQUEST_ID) {
            require(committedMove.fulfilled, "AsyncHandler: latest committed move not fulfilled");
        } else {
            revert("AsyncHandler: no committed move for game");
        }
        return requestToCommittedMove[latestReqId];
    }

    function hasCommittedAction(uint256 gameId) internal view returns (bool) {
        return _hasCommittedAction[gameId];
    }

    function hasCommittedMove(uint256 gameId) internal view returns (bool) {
        return _hasCommittedAction[gameId];
    }

    function _fulfillCommittedMove(uint256 reqId, bytes memory clearTexts) internal {
        CommittedMoveData storage committedMove = requestToCommittedMove[reqId];
        uint8 rawCard = abi.decode(clearTexts, (uint8));
        committedMove.decryptedCard = CardLib.toCard(rawCard);
        committedMove.fulfilled = true;
    }

    function _clearLatestCommittedMove(uint256 gameId) internal {
        uint256 latestReqId = gameIdToLatestCommittedMoveRequestId[gameId];
        if (latestReqId != DEFAULT_REQUEST_ID) {
            _hasCommittedAction[gameId] = false;
            gameIdToLatestCommittedMoveRequestId[gameId] = DEFAULT_REQUEST_ID;
        }
    }

    function handleCommitMove(uint256 requestId, bytes memory clearTexts, bytes memory signatures) external virtual;
    function handleCommitMarketDeck(uint256 requestId, bytes memory clearTexts, bytes memory signatures)
        external
        virtual;
}
