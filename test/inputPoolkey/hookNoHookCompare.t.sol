// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "v4-core/src/interfaces/IProtocolFees.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {MockHooks} from "v4-core/src/test/MockHooks.sol";
import {MockContract} from "v4-core/src/test/MockContract.sol";
import {EmptyTestHooks} from "v4-core/src/test/EmptyTestHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {TestInvalidERC20} from "v4-core/src/test/TestInvalidERC20.sol";
import {PoolEmptyUnlockTest} from "v4-core/src/test/PoolEmptyUnlockTest.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {AmountHelpers} from "v4-core/test/utils/AmountHelpers.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {setupContract} from "./setupContract.sol";

// Routers
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {Action, PoolNestedActionsTest} from "v4-core/src/test/PoolNestedActionsTest.sol";
import {Actions, ActionsRouter} from "v4-core/src/test/ActionsRouter.sol";

contract PoolManagerTest is Test, Deployers, setupContract {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    PoolKey emptyHook;
    function setUp() public {
        console.log("setup start :", gasleft());
        setupPoolkey();

        (uint160 sqrtPriceX96, , uint24 pf, uint24 lpfee) = manager.getSlot0(key.toId());
        (emptyHook, ) = initPool(
            key.currency0,
            key.currency1,
            IHooks(address(0)),
            lpfee,
            key.tickSpacing,
            sqrtPriceX96
        );

        console.log("setup end:", gasleft());
    }

    function test_addLiquidityWithHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_addLiquidity(key);
    }
    function test_addLiquidityWithNoHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_addLiquidity(emptyHook);
    }
    function test_addLiquidity(PoolKey memory keys) internal {
        uint256 start;
        uint256 end;
        
        if (keys.currency0.isAddressZero()) {
            start = gasleft();
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            end = gasleft();
        } else {
            start = gasleft();
            modifyLiquidityRouter.modifyLiquidity(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            end = gasleft();
        }
        if (address(keys.hooks) == address(0x0)) {
            console.log("no-hook-add-gas-using : ", (start - end));
            console.log("no-hook-add-gasPrice-using : ", tx.gasprice);
            console.log("no-hook-add-totalGas-using : ", (start - end) * tx.gasprice);
        } else {
            console.log("hook-add-gas-using : ", (start - end));
            console.log("hook-add-gasPrice-using : ", tx.gasprice);
            console.log("hook-add-totalGas-using : ", (start - end) * tx.gasprice);
        }
    }

    function test_removeLiquidityWithHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_removeLiquidity(key);
    }
    function test_removeLiquidityWithNoHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_removeLiquidity(emptyHook);
    }
    function test_removeLiquidity(PoolKey memory keys) internal {
        uint256 start;
        uint256 end;

        if (keys.currency0.isAddressZero()) {
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            
            start = gasleft();
            modifyLiquidityRouter.modifyLiquidity(keys, CUSTOM_REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            end = gasleft();
        } else {
            modifyLiquidityRouter.modifyLiquidity(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            
            start = gasleft();
            modifyLiquidityRouter.modifyLiquidity(keys, CUSTOM_REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            end = gasleft();
        }
        if (address(keys.hooks) == address(0x0)) {
            console.log("no-hook-remove-gas-using : ", (start - end));
            console.log("no-hook-remove-gasPrice-using : ", tx.gasprice);
            console.log("no-hook-remove-totalGas-using : ", (start - end) * tx.gasprice);
        } else {
            console.log("hook-remove-gas-using : ", (start - end));
            console.log("hook-remove-gasPrice-using : ", tx.gasprice);
            console.log("hook-remove-totalGas-using : ", (start - end) * tx.gasprice);
        }
    }

    function test_donateWithHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_donate(key);
    }
    function test_donateWithNoHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_donate(emptyHook);
    }
    function test_donate(PoolKey memory keys) internal {
        uint256 start;
        uint256 end;

        if (keys.currency0.isAddressZero()) {
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            
            start = gasleft();
            donateRouter.donate{value: 100}(keys, 100, 200, ZERO_BYTES);
            end = gasleft();
        } else {
            modifyLiquidityRouter.modifyLiquidity(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            
            start = gasleft();
            donateRouter.donate(keys, 100, 200, ZERO_BYTES);
            end = gasleft();
        }

        if (address(keys.hooks) == address(0x0)) {
            console.log("no-hook-donate-gas-using : ", (start - end));
            console.log("no-hook-donate-gasPrice-using : ", tx.gasprice);
            console.log("no-hook-donate-totalGas-using : ", (start - end) * tx.gasprice);
        } else {
            console.log("hook-donate-gas-using : ", (start - end));
            console.log("hook-donate-gasPrice-using : ", tx.gasprice);
            console.log("hook-donate-totalGas-using : ", (start - end) * tx.gasprice);
        }
    }

    function test_swapWithHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_swap(key);
    }
    function test_swapWithNoHook() public {
        vm.startPrank(txOrigin, txOrigin);
        test_swap(emptyHook);
    }
    function test_swap(PoolKey memory keys) internal {
        uint256 start;
        uint256 end;

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});
        BalanceDelta balance;

        if (key.currency0.isAddressZero()) {
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            
            start = gasleft();
            balance = swapRouter.swap{value: 100}(keys, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            end = gasleft();
        } else {
            modifyLiquidityRouter.modifyLiquidity(keys, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
            
            start = gasleft();
            balance = swapRouter.swap(keys, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            end = gasleft();
        }

        (
            uint160 sqrtPrice,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        ) = manager.getSlot0(keys.toId());
        if (address(keys.hooks) == address(0x0)) {
            console.log("no-hook-Swap-tokenPrice-using : ", sqrtPrice);
            console.log("no-hook-Swap-protocolFee-using : ", protocolFee);
            console.log("no-hook-Swap-lpFee-using : ", lpFee);
            console.log("no-hook-Swap-balance-amount0-using : ", balance.amount0());
            console.log("no-hook-Swap-balance-amount1-using : ", balance.amount1());
            console.log("no-hook-swap-gas-using : ", (start - end));
            console.log("no-hook-swap-gasPrice-using : ", tx.gasprice);
            console.log("no-hook-swap-totalGas-using : ", (start - end) * tx.gasprice);
        } else {
            console.log("hook-Swap-tokenPrice-using : ", sqrtPrice);
            console.log("hook-Swap-protocolFee-using : ", protocolFee);
            console.log("hook-Swap-lpFee-using : ", lpFee);
            console.log("hook-Swap-balance-amount0-using : ", balance.amount0());
            console.log("hook-Swap-balance-amount1-using : ", balance.amount1());
            console.log("hook-swap-gas-using : ", (start - end));
            console.log("hook-swap-gasPrice-using : ", tx.gasprice);
            console.log("hook-swap-totalGas-using : ", (start - end) * tx.gasprice);
        }
    }
}
