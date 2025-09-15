// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IRuleSet} from "../interfaces/IRuleSet.sol";
import {Action, GameStatus, PendingAction} from "./CardEngineLib.sol";

library ConditionalsLib {
    function eqs(Action a, Action b) internal pure returns (bool c) {
        assembly {
            c := eq(a, b)
        }
    }

    function eqs(PendingAction a, PendingAction b) internal pure returns (bool c) {
        assembly {
            c := eq(a, b)
        }
    }

    function eqs(GameStatus a, GameStatus b) internal pure returns (bool c) {
        assembly {
            c := eq(a, b)
        }
    }

    function eqsOr(Action a, Action b, Action c) internal pure returns (bool d) {
        assembly {
            d := or(eq(a, b), eq(a, c))
        }
    }

    function eqsOr(PendingAction a, PendingAction b, PendingAction c) internal pure returns (bool d) {
        assembly {
            d := or(eq(a, b), eq(a, c))
        }
    }

    function eqsOr(GameStatus a, GameStatus b, GameStatus c) internal pure returns (bool d) {
        assembly {
            d := or(eq(a, b), eq(a, c))
        }
    }

    function notEqs(Action a, Action b) internal pure returns (bool c) {
        assembly {
            c := iszero(eq(a, b))
        }
    }

    function notEqs(PendingAction a, PendingAction b) internal pure returns (bool c) {
        assembly {
            c := iszero(eq(a, b))
        }
    }

    function notEqs(GameStatus a, GameStatus b) internal pure returns (bool c) {
        assembly {
            c := iszero(eq(a, b))
        }
    }

    function notEqs(IRuleSet.EngineOp a, IRuleSet.EngineOp b) internal pure returns (bool c) {
        assembly {
            c := iszero(eq(a, b))
        }
    }
}
