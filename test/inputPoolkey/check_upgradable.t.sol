// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolEmptyUnlockTest} from "v4-core/src/test/PoolEmptyUnlockTest.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {setupContract} from "./setupContract.sol";

contract upgradableTest is Test, setupContract {
    using Hooks for IHooks;
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    function setUp() public {
        setupPoolkey();
    }

    function test_isProxy() public {
        bytes32 slot0 = vm.load(address(key.hooks), 0);
        address couldBeImplementation = address(uint160(uint(slot0)));
        if (couldBeImplementation != address(0)) {
            bool isImplementation = couldBeImplementation.code.length > 0;
            assertFalse(isImplementation, "Hook might be a proxy");
        }

    }
}