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

contract onlyByPoolManagerTest is Test, Deployers, setupContract {
    using Hooks for IHooks;
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    BalanceDelta balanceDelta = BalanceDeltaLibrary.ZERO_DELTA;
    function setUp() public {
        setupPoolkey();
    }

    function test_beforeInitialize() public {
        if (key.hooks.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG)) {
            try key.hooks.beforeInitialize(address(this), key, SQRT_PRICE_1_1) {
                revert("Expected NotPoolManager : beforeInitialize must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_afterInitialize() public {
        if (key.hooks.hasPermission(Hooks.AFTER_INITIALIZE_FLAG)) {
            try key.hooks.afterInitialize(address(this), key, SQRT_PRICE_1_1, 0) {
                revert("Expected NotPoolManager : afterInitialize must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_beforeAddLiquidity() public {
        if (key.hooks.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG)) {
            try key.hooks.beforeAddLiquidity(address(this), key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeAddLiquidity must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_afterAddLiquidity() public {
        if (key.hooks.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG)) {
            try key.hooks.afterAddLiquidity(address(this), key, CUSTOM_LIQUIDITY_PARAMS, balanceDelta, balanceDelta, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterAddLiquidity must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_beforeRemoveLiquidity() public {
        if (key.hooks.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)) {
            try key.hooks.beforeRemoveLiquidity(address(this), key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeRemoveLiquidity must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_afterRemoveLiquidity() public {
        if (key.hooks.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)) {
            try key.hooks.afterRemoveLiquidity(address(this), key, CUSTOM_LIQUIDITY_PARAMS, balanceDelta, balanceDelta, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterRemoveLiquidity must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_beforeSwap() public {
        if (key.hooks.hasPermission(Hooks.BEFORE_SWAP_FLAG)) {
            try key.hooks.beforeSwap(address(this), key, CUSTOM_SWAP_PARAMS, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeSwap must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_afterSwap() public {
        if (key.hooks.hasPermission(Hooks.AFTER_SWAP_FLAG)) {
            try key.hooks.afterSwap(address(this), key, CUSTOM_SWAP_PARAMS, balanceDelta, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterSwap must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_beforeDonate() public {
        if (key.hooks.hasPermission(Hooks.BEFORE_DONATE_FLAG)) {
            try key.hooks.beforeDonate(address(this), key, 0, 0, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeDonate must be called only by PoolManager");
            } catch  {}
        }
    }

    function test_afterDonate() public {
        if (key.hooks.hasPermission(Hooks.AFTER_DONATE_FLAG)) {
            try key.hooks.afterDonate(address(this), key, 0, 0, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterDonate must be called only by PoolManager");
            } catch  {}
        }
    }
}
