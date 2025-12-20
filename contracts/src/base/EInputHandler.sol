// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
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
    bytes externalInput;
}

abstract contract EInputHandler is ZamaEthereumConfig {
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

        _fheAllowThis(out[0]);
        _fheAllowThis(out[1]);
    }

    function _verifyExternalInputData(EInputData calldata einputData, bytes calldata inputProof)
        internal
        returns (euint256 out)
    {
        if (einputData.inputType == InputType._EUINT8) {
            euint8 value = FHE.fromExternal(abi.decode(einputData.externalInput, (externalEuint8)), inputProof);
            return FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT16) {
            euint16 value = FHE.fromExternal(abi.decode(einputData.externalInput, (externalEuint16)), inputProof);
            return FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT32) {
            euint32 value = FHE.fromExternal(abi.decode(einputData.externalInput, (externalEuint32)), inputProof);
            return FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT64) {
            euint64 value = FHE.fromExternal(abi.decode(einputData.externalInput, (externalEuint64)), inputProof);
            return FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT128) {
            euint128 value = FHE.fromExternal(abi.decode(einputData.externalInput, (externalEuint128)), inputProof);
            return FHE.asEuint256(value);
        }
        if (einputData.inputType == InputType._EUINT256) {
            return FHE.fromExternal(abi.decode(einputData.externalInput, (externalEuint256)), inputProof);
        }
    }

    function _fheAllowThis(euint256 value) internal {
        FHE.allowThis(value);
    }
}
