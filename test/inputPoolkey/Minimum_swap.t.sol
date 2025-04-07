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
import {PoolId} from "v4-core/src/types/PoolId.sol";
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

contract Minimum_swap is Test, Deployers, setupContract {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    function setUp() public {
        setupPoolkey();
    }

    function test_swap_succeedsIfInitialized() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});
        
        if (currency0.isAddressZero())
            swapRouter.swap{value: 100}(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_swap_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        if (currency0.isAddressZero())
            swapRouter.swap{value: 100}(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
        // snapLastCall("simple swap");
    }

    function test_swap_mint6909IfOutputNotTaken_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: MAX_PRICE_LIMIT});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        if (currency0.isAddressZero())
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);

        // snapLastCall("swap mint output as 6909");
    }

    function test_swap_burn6909AsInput_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 10 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -1 ether, sqrtPriceLimitX96: MAX_PRICE_LIMIT});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        if (currency0.isAddressZero()) {
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
            params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 25, sqrtPriceLimitX96: MIN_PRICE_LIMIT});
        }
        else {
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            params = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: 25, sqrtPriceLimitX96: MAX_PRICE_LIMIT});
        }

        // give permission for swapRouter to burn the 6909s
        manager.setOperator(address(swapRouter), true);

        // swap from currency1 to currency0 again, using 6909s as input tokens
        testSettings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: true});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        // snapLastCall("swap burn 6909 for input");
    }

    function test_swap_againstLiquidity_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: MIN_PRICE_LIMIT});
        
        if (currency0.isAddressZero()) {
            swapRouter.swap{value: 1 ether}(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);
        }
        else {
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        }   
        // snapLastCall("swap against liquidity");
    }
}
