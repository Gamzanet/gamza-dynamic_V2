// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "v4-core/src/interfaces/IProtocolFees.sol";
import {IProtocolFeeController} from "v4-core/src/interfaces/IProtocolFeeController.sol";
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
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
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
import {PoolModifyLiquidityTestNoChecks} from "v4-core/src/test/PoolModifyLiquidityTestNoChecks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapRouterNoChecks} from "v4-core/src/test/SwapRouterNoChecks.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {Action, PoolNestedActionsTest} from "v4-core/src/test/PoolNestedActionsTest.sol";
import {ProtocolFeeControllerTest} from "v4-core/src/test/ProtocolFeeControllerTest.sol";
import {Actions, ActionsRouter} from "v4-core/src/test/ActionsRouter.sol";

contract PoolManagerTest is Test, Deployers, GasSnapshot, setupContract {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    function setUp() public {
        setupPoolkey();
    }

    function test_addLiquidity_6909() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);

        // convert test tokens into ERC6909 claims
        if (currency0.isAddressZero())
            claimsRouter.deposit{value: 100 ether}(currency0, address(txOrigin), 100 ether);
        else
            claimsRouter.deposit(currency0, address(txOrigin), 100 ether);
        claimsRouter.deposit(currency1, address(txOrigin), 100 ether);
        assertEq(manager.balanceOf(address(txOrigin), currency0.toId()), 100 ether);
        assertEq(manager.balanceOf(address(txOrigin), currency1.toId()), 100 ether);

        uint256 currency0BalanceBefore = currency0.balanceOf(txOrigin);
        uint256 currency1BalanceBefore = currency1.balanceOf(txOrigin);

        // allow liquidity router to burn our 6909 tokens
        manager.setOperator(address(modifyLiquidityRouter), true);

        BalanceDelta delta;
        // add liquidity with 6909: settleUsingBurn=true, takeClaims=true (unused)
        delta = modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES, true, true);

        assertLt(manager.balanceOf(address(txOrigin), currency0.toId()), 100 ether);
        assertLt(manager.balanceOf(address(txOrigin), currency1.toId()), 100 ether);

        // ERC20s are unspent
        assertEq(currency0.balanceOf(txOrigin), currency0BalanceBefore);
        assertEq(currency1.balanceOf(txOrigin), currency1BalanceBefore);
    }

    function test_removeLiquidity_6909() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        if (key.currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);

        assertEq(manager.balanceOf(address(txOrigin), currency0.toId()), 0);
        assertEq(manager.balanceOf(address(txOrigin), currency1.toId()), 0);

        uint256 currency0BalanceBefore = currency0.balanceOf(txOrigin);
        uint256 currency1BalanceBefore = currency1.balanceOf(txOrigin);

        // remove liquidity as 6909: settleUsingBurn=true (unused), takeClaims=true
        modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES, true, true);

        assertTrue(manager.balanceOf(address(txOrigin), currency0.toId()) > 0);
        assertTrue(manager.balanceOf(address(txOrigin), currency1.toId()) > 0);

        // ERC20s are unspent
        assertEq(currency0.balanceOf(txOrigin), currency0BalanceBefore);
        assertEq(currency1.balanceOf(txOrigin), currency1BalanceBefore);
    }

    function test_addLiquidity_secondAdditionSameRange_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        IPoolManager.ModifyLiquidityParams memory uniqueParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -(5*key.tickSpacing), tickUpper: -(3*key.tickSpacing), liquidityDelta: 1 ether, salt: 0});
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);
        snapLastCall("simple addLiquidity second addition same range");
    }

    function test_removeLiquidity_someLiquidityRemains_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        // add double the liquidity to remove
        IPoolManager.ModifyLiquidityParams memory uniqueParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -(5*key.tickSpacing), tickUpper: -(3*key.tickSpacing), liquidityDelta: 1 ether, salt: 0});
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);

        uniqueParams.liquidityDelta /= -2;
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);
        snapLastCall("simple removeLiquidity some liquidity remains");
    }

    function test_addLiquidity_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.stopPrank();
        snapLastCall("simple addLiquidity");
    }

    function test_removeLiquidity_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("simple removeLiquidity");
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
        if (currency0.isAddressZero())
            swapRouterNoChecks.swap{value: 100}(key, CUSTOM_SWAP_PARAMS);
        else
            swapRouterNoChecks.swap(key, CUSTOM_SWAP_PARAMS);
        snapLastCall("simple swap");
    }

    function test_swap_mint6909IfOutputNotTaken_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        if (currency0.isAddressZero())
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);

        snapLastCall("swap mint output as 6909");
    }

    function test_swap_burn6909AsInput_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        if (currency0.isAddressZero()) {
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
            params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 25, sqrtPriceLimitX96: SQRT_PRICE_1_4});
        }
        else {
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            params = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: 25, sqrtPriceLimitX96: SQRT_PRICE_4_1});
        }

        // give permission for swapRouter to burn the 6909s
        manager.setOperator(address(swapRouter), true);

        // swap from currency1 to currency0 again, using 6909s as input tokens
        testSettings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: true});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapLastCall("swap burn 6909 for input");
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
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_4});
        
        if (currency0.isAddressZero()) {
            swapRouter.swap{value: 1 ether}(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);
        }
        else {
            swapRouter.swap(key, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        }   
        snapLastCall("swap against liquidity");
    }

    // test successful donation if pool has liquidity
    function test_donate_succeedsWhenPoolHasLiquidity() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(key.toId());
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);

        if (currency0.isAddressZero())
            donateRouter.donate{value: 100}(key, 100, 200, ZERO_BYTES);
        else
            donateRouter.donate(key, 100, 200, ZERO_BYTES);

        snapLastCall("donate gas with 2 tokens");

        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(key.toId());
        assertEq(feeGrowthGlobal0X128, 34028236692093846346337);
        assertEq(feeGrowthGlobal1X128, 68056473384187692692674);
    }

    function test_donate_OneToken_gas() public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        donateRouter.donate(key, 0, 100, ZERO_BYTES);
        snapLastCall("donate gas with 1 token");
    }

    function test_fuzz_donate_emits_event(uint256 amount0, uint256 amount1) public {
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        amount0 = bound(amount0, 0, uint256(int256(type(int128).max) / 2));
        amount1 = bound(amount1, 0, uint256(int256(type(int128).max) / 2));

        vm.expectEmit(true, true, false, true, address(manager));
        emit Donate(key.toId(), address(donateRouter), uint256(amount0), uint256(amount1));
        if (currency0.isAddressZero()) {
            vm.deal(address(txOrigin), Constants.MAX_UINT256);
            donateRouter.donate{value: amount0}(key, amount0, amount1, ZERO_BYTES);
        }
        else
            donateRouter.donate(key, amount0, amount1, ZERO_BYTES);
    }
}
