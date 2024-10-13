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

contract PoolManagerTest is Test, Deployers, GasSnapshot {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    event UnlockCallback();
    event ProtocolFeeControllerUpdated(address feeController);
    event ModifyLiquidity(
        PoolId indexed poolId,
        address indexed sender,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bytes32 salt
    );
    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    event Donate(PoolId indexed id, address indexed sender, uint256 amount0, uint256 amount1);

    event Transfer(
        address caller, address indexed sender, address indexed receiver, uint256 indexed id, uint256 amount
    );

    uint24 constant MAX_PROTOCOL_FEE_BOTH_TOKENS = (1000 << 12) | 1000; // 1000 1000

    PoolKey inputkey;
    address hookAddr;
    function setUp() public {
        // string memory code_json = vm.readFile("test/inputPoolkey/patched_TakeProfitsHook.json");
        string memory code_json = vm.readFile("test/inputPoolkey/patched_Allhook.json");

        address _currency0 = vm.parseJsonAddress(code_json, ".data.currency0");
        address _currency1 = vm.parseJsonAddress(code_json, ".data.currency1");
        uint24 _fee = uint24(vm.parseJsonUint(code_json, ".data.fee"));
        int24 _tickSpacing = int24(vm.parseJsonInt(code_json, ".data.tickSpacing"));
        address _hooks = vm.parseJsonAddress(code_json, ".data.hooks");

        inputkey.currency0 = Currency.wrap(_currency0);
        inputkey.currency1 = Currency.wrap(_currency1);
        inputkey.fee = _fee;
        inputkey.tickSpacing = _tickSpacing;
        inputkey.hooks = IHooks(_hooks);

        checkFlag();

        hookAddr = address(inputkey.hooks);

        custom_deployFreshManagerAndRouters();
        if (!inputkey.currency0.isAddressZero()) custom_ApproveCurrency(inputkey.currency0);
        custom_ApproveCurrency(inputkey.currency1);
    }

    function test_initialize_succeedsWithHooks(uint160 sqrtPriceX96) public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_INITIALIZE_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_INITIALIZE_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(mockAddr), inputkey.fee, inputkey.tickSpacing, sqrtPriceX96);
    }

    function test_addLiquidity_succeedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(mockAddr), inputkey.fee, inputkey.tickSpacing, sqrtPriceX96);
        
        BalanceDelta balanceDelta;
        if (currency0.isAddressZero()) balanceDelta = modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else balanceDelta = modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        
        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG)) {
            bytes32 beforeSelector = MockHooks.beforeAddLiquidity.selector;
            bytes memory beforeParams = abi.encode(address(modifyLiquidityRouter), key, LIQUIDITY_PARAMS, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)) {
            bytes32 afterSelector = MockHooks.afterAddLiquidity.selector;
            bytes memory afterParams = abi.encode(
                address(modifyLiquidityRouter),
                key,
                LIQUIDITY_PARAMS,
                balanceDelta,
                BalanceDeltaLibrary.ZERO_DELTA,
                ZERO_BYTES
            );
            assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
        }
    }

    function test_removeLiquidity_succeedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(mockAddr), inputkey.fee, inputkey.tickSpacing, sqrtPriceX96);
        
        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        
        BalanceDelta balanceDelta;
        if (currency0.isAddressZero()) balanceDelta = modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        else balanceDelta = modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);

        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)) {
            bytes32 beforeSelector = MockHooks.beforeRemoveLiquidity.selector;
            bytes memory beforeParams = abi.encode(address(modifyLiquidityRouter), key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)) {
            bytes32 afterSelector = MockHooks.afterRemoveLiquidity.selector;
            bytes memory afterParams = abi.encode(
                address(modifyLiquidityRouter),
                key,
                REMOVE_LIQUIDITY_PARAMS,
                balanceDelta,
                BalanceDeltaLibrary.ZERO_DELTA,
                ZERO_BYTES
            );
            assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
        }
    }

    function test_addLiquidity_failsWithIncorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);
        
        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));

        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG)) {
            // Fails at beforeAddLiquidity hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
            else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)) {
            // Fail at afterAddLiquidity hook.
            mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
            else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);        }
    }

    function test_removeLiquidity_failsWithIncorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
        
        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        
        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, bytes4(0xdeadbeef));

        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)) {
            // Fails at beforeRemoveLiquidity hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            else modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)) {
            // Fail at afterRemoveLiquidity hook.
            mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, mockHooks.beforeRemoveLiquidity.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            else modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        }
    }

    function test_addLiquidity_succeedsWithCorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, mockHooks.afterAddLiquidity.selector);

        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_succeedsWithCorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
        
        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, mockHooks.beforeRemoveLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, mockHooks.afterRemoveLiquidity.selector);

        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_withHooks_gas() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);

        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("addLiquidity with hook");
    }

    function test_removeLiquidity_withHooks_gas() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);

        if (currency0.isAddressZero()) {
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
            modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        }

        snapLastCall("removeLiquidity with hook");
    }

    function test_swap_succeedsWithHooksIfInitialized() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        if (inputkey.currency0.isAddressZero()) {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(mockAddr), inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(mockAddr), inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        BalanceDelta balanceDelta;
        if (inputkey.currency0.isAddressZero()) balanceDelta = swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        else balanceDelta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG)) {
            bytes32 beforeSelector = MockHooks.beforeSwap.selector;
            bytes memory beforeParams = abi.encode(address(swapRouter), key, SWAP_PARAMS, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)) {
            bytes32 afterSelector = MockHooks.afterSwap.selector;
            bytes memory afterParams = abi.encode(address(swapRouter), key, SWAP_PARAMS, balanceDelta, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
        }
    }

    function test_swap_failsWithIncorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);
        
        if (inputkey.currency0.isAddressZero()) {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_PRICE_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG)) {
            // Fails at beforeSwap hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (inputkey.currency0.isAddressZero()) swapRouter.swap{value: 100}(key, swapParams, testSettings, ZERO_BYTES);
            else swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)) {
            // Fail at afterSwap hook.
            mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (inputkey.currency0.isAddressZero()) swapRouter.swap{value: 100}(key, swapParams, testSettings, ZERO_BYTES);
            else swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        }
    }

    function test_swap_succeedsWithCorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        if (inputkey.currency0.isAddressZero()) {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: SQRT_PRICE_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        if (inputkey.currency0.isAddressZero()) swapRouter.swap{value: 100}(key, swapParams, testSettings, ZERO_BYTES);
        else swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_withHooks_gas() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        if (inputkey.currency0.isAddressZero()) {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        if (inputkey.currency0.isAddressZero()) swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        else swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_4});
        testSettings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        if (inputkey.currency0.isAddressZero()) swapRouter.swap{value: 100}(key, swapParams, testSettings, ZERO_BYTES);
        else swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapLastCall("swap with hooks");
    }

    function test_donate_failsWithIncorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_DONATE_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_DONATE_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        if (inputkey.currency0.isAddressZero()) {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));
        
        if (Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_DONATE_FLAG)) {
            // Fails at beforeDonate hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (inputkey.currency0.isAddressZero()) donateRouter.donate{value: 100}(key, 100, 200, ZERO_BYTES);
            else donateRouter.donate(key, 100, 200, ZERO_BYTES);
        }
        if (Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_DONATE_FLAG)) {
            // Fail at afterDonate hook.
            mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            if (inputkey.currency0.isAddressZero()) donateRouter.donate{value: 100}(key, 100, 200, ZERO_BYTES);
            else donateRouter.donate(key, 100, 200, ZERO_BYTES);
        }
    }

    function test_donate_succeedsWithCorrectSelectors() public {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_DONATE_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_DONATE_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        if (inputkey.currency0.isAddressZero()) {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        else {
            (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);

        if (inputkey.currency0.isAddressZero()) donateRouter.donate{value: 100}(key, 100, 200, ZERO_BYTES);
        else donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function custom_deployFreshManagerAndRouters() internal {
        // unichain-sepolia
        // manager = IPoolManager(0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967);
        manager = new PoolManager();

        swapRouter = new PoolSwapTest(manager);
        swapRouterNoChecks = new SwapRouterNoChecks(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        claimsRouter = new PoolClaimsTest(manager);
        nestedActionRouter = new PoolNestedActionsTest(manager);
        feeController = new ProtocolFeeControllerTest();
        actionsRouter = new ActionsRouter(manager);

        manager.setProtocolFeeController(feeController);
    }

    function custom_ApproveCurrency(Currency currency) internal {
        MockERC20 token = MockERC20(Currency.unwrap(currency));
        
        deal(address(token), address(this), type(uint256).max);
        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], Constants.MAX_UINT256);
        }
    }

    event permission(Hooks.Permissions);
    function checkFlag() public {
        Hooks.Permissions memory flag;
        (,bytes memory returnData) = address(inputkey.hooks).call(abi.encodeWithSignature("getHookPermissions()"));
        flag = abi.decode(returnData, (Hooks.Permissions));
        emit permission(flag);
    }
}
