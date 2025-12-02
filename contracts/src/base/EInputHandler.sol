// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {
    FHE,
    euint128,
    euint16,
    euint256,
    euint32,
    euint64,
    euint8,
    externalEuint128,
    externalEuint16,
    externalEuint256,
    externalEuint32,
    externalEuint64,
    externalEuint8
} from "@fhevm/solidity/lib/FHE.sol";

enum InputType {
    _EMPTY,
    _EUINT8,
    _EUINT16,
    _EUINT32,
    _EUINT64,
    _EUINT128,
    _EUINT256
}

struct EInputData {
    InputType inputType;
    externalEuint8 inputEuint8;
    externalEuint16 inputEuint16;
    externalEuint32 inputEuint32;
    externalEuint64 inputEuint64;
    externalEuint128 inputEuint128;
    externalEuint256 inputEuint256;
}

abstract contract EInputHandler is SepoliaConfig {
    error EInputData_inputTypeCannotBeEmpty();

    function _handleInputData(EInputData calldata einput0, EInputData calldata einput1, bytes calldata inputProof)
        internal
        returns (euint256[2] memory out)
    {
        if (einput0.inputType == InputType._EMPTY) {
            revert EInputData_inputTypeCannotBeEmpty();
        }
        out[0] = _verifyExternalInputData(einput0, inputProof);
        out[1] = _verifyExternalInputData(einput1, inputProof);

        FHE.allowThis(out[0]);
        FHE.allowThis(out[1]);
    }

    function _verifyExternalInputData(EInputData calldata einputData, bytes calldata inputProof)
        internal
        returns (euint256 out)
    {
        if (einputData.inputType == InputType._EUINT8) {
            euint8 value = FHE.fromExternal(einputData.inputEuint8, inputProof);
            out = FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT16) {
            euint16 value = FHE.fromExternal(einputData.inputEuint16, inputProof);
            out = FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT32) {
            euint32 value = FHE.fromExternal(einputData.inputEuint32, inputProof);
            out = FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT64) {
            euint64 value = FHE.fromExternal(einputData.inputEuint64, inputProof);
            out = FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT128) {
            euint128 value = FHE.fromExternal(einputData.inputEuint128, inputProof);
            out = FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT256) {
            out = FHE.fromExternal(einputData.inputEuint256, inputProof);
        }
    }
}
