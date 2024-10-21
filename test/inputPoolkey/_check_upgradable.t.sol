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


contract DoubleInitHookTest is Test {
    using Hooks for IHooks;
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    address public hookAddr;
    Currency currency0;
    Currency currency1;
    IPoolManager manager = IPoolManager(0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967);
    PoolKey key;

    bytes constant ZERO_BYTES = Constants.ZERO_BYTES;
    uint160 constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;

    function test_if_proxy() public {
        string memory code_json = vm.readFile("test/inputPoolkey/proxyHook.json");
        address _currency0 = vm.parseJsonAddress(code_json, ".data.currency0");
        address _currency1 = vm.parseJsonAddress(code_json, ".data.currency1");
        uint24 _fee = uint24(vm.parseJsonUint(code_json, ".data.fee"));
        int24 _tickSpacing = int24(vm.parseJsonInt(code_json, ".data.tickSpacing"));
        hookAddr = vm.parseJsonAddress(code_json, ".data.hooks");
        currency0 = Currency.wrap(_currency0);
        currency1 = Currency.wrap(_currency1);

        key = PoolKey(currency0, currency1, _fee+1, 60, IHooks(hookAddr));

        bytes32 slot0 = vm.load(hookAddr, 0);
        address couldBeImplementation = address(uint160(uint(slot0)));
        if (couldBeImplementation != address(0)) {
            bool isImplementation = couldBeImplementation.code.length > 0;
            assertFalse(isImplementation, "Hook might be a proxy");
        }

    }
}