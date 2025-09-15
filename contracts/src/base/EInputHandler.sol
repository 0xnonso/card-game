// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    FHE, euint128, euint256, euint64, externalEuint128, externalEuint256, externalEuint64
} from "fhevm/lib/FHE.sol";

contract EInputHandler {
    enum InputOneType {
        _EUINT64,
        _EUINT128,
        _EUINT256
    }

    struct EInputData {
        externalEuint256 inputZero;
        InputOneType inputOneType;
        externalEuint64 inputOne64;
        externalEuint128 inputOne128;
        externalEuint256 inputOne256;
    }

    function _handleInputData(EInputData calldata einputData, bytes calldata inputProof)
        internal
        returns (euint256[2] memory out)
    {
        out[0] = FHE.fromExternal(einputData.inputZero, inputProof);
        if (einputData.inputOneType == InputOneType._EUINT64) {
            euint64 value = FHE.fromExternal(einputData.inputOne64, inputProof);
            out[1] = FHE.asEuint256(value);
        }
        if (einputData.inputOneType == InputOneType._EUINT128) {
            euint128 value = FHE.fromExternal(einputData.inputOne128, inputProof);
            out[1] = FHE.asEuint256(value);
        }
        if (einputData.inputOneType == InputOneType._EUINT256) {
            euint256 value = FHE.fromExternal(einputData.inputOne256, inputProof);
            out[1] = value;
        }
    }
}
