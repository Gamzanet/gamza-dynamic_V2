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
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TestInvalidERC20} from "v4-core/src/test/TestInvalidERC20.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolEmptyUnlockTest} from "v4-core/src/test/PoolEmptyUnlockTest.sol";
import {Action} from "v4-core/src/test/PoolNestedActionsTest.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {AmountHelpers} from "v4-core/test/utils/AmountHelpers.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {IProtocolFees} from "v4-core/src/interfaces/IProtocolFees.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Actions} from "v4-core/src/test/ActionsRouter.sol";

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

    address hookAddr;
    Hooks.Permissions flag;
    uint24 FEE;
    function timeWarp(uint256 timeToAdd) internal {
        uint256 currentTime = block.timestamp;
        uint256 tmptime = uint256(currentTime) - 1;
        vm.warp(currentTime + timeToAdd);
        uint256 newTime = block.timestamp;

        assertEq(newTime, uint256(tmptime + timeToAdd ) + 1, "Time did not warp correctly");
        console.log("warp end");
        
    }
    function setUp() public {
        address forFlag = address(uint160(Hooks.ALL_HOOK_MASK));

        // dynamic
        // string memory code_json = vm.readFile("test/inputBytecode/patched_GasPriceFeesHook.json");
        string memory code_json = vm.readFile("test/inputBytecode/patched_PointsHook.json");
        // string memory code_json = vm.readFile("test/inputBytecode/patched_TakeProfitsHook.json");

        bytes memory _bytecode = vm.parseJsonBytes(code_json, ".bytecode.object");
        bytes memory _deployBytecode = vm.parseJsonBytes(code_json, ".deployedBytecode.object"); // runtimecode
        vm.etch(forFlag, _deployBytecode);

        (bool success, bytes memory returnData) = forFlag.call(abi.encodeWithSignature("getHookPermissions()"));
        flag = abi.decode(returnData, (Hooks.Permissions));
        hookAddr = generateHookAddress();
        // (bool success, bytes memory returnData) = addr.call(abi.encodeWithSignature("isDynamicFee()"));
        // bool isDynamic = abi.decode(returnData, (bool));
        // FEE = isDynamic ? LPFeeLibrary.DYNAMIC_FEE_FLAG : Constants.FEE_MEDIUM;

        // FEE = LPFeeLibrary.DYNAMIC_FEE_FLAG;
        FEE = Constants.FEE_MEDIUM;

        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));

        bytes memory withconstructor = abi.encodePacked(_bytecode, abi.encode(manager, "test", "test"));
        vm.etch(hookAddr, withconstructor);
        (success, returnData) = hookAddr.call("");
        vm.etch(hookAddr, returnData);

        console.log("setup End");
    }
    function test_initialize_atSpecificTime1Day(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 1 days;
        console.log("start");
        console.log("lv1");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv2");
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv3");
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv4");
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv5");
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv6");
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv7");
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv8");
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv9");
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv10");
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv11");
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv12");
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv13");
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv14");
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv15");
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv16");
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv17");
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv18");
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv19");
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv20");
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv21");
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv22");
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }

    function test_initialize_atSpecificTime1Week(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 7 days;
        console.log("start");
        console.log("lv1");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv2");
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv3");
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv4");
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv5");
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv6");
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv7");
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv8");
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv9");
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv10");
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv11");
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv12");
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv13");
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv14");
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv15");
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv16");
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv17");
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv18");
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv19");
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv20");
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv21");
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv22");
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_atSpecificTime1Month(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 30 days;
        console.log("start");
        console.log("lv1");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv2");
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv3");
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv4");
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv5");
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv6");
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv7");
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv8");
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv9");
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv10");
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv11");
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv12");
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv13");
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv14");
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv15");
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv16");
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv17");
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv18");
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv19");
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv20");
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv21");
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv22");
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_atSpecificTime1Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 365 days;
        console.log("start");
        console.log("lv1");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv2");
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv3");
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv4");
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv5");
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv6");
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv7");
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv8");
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv9");
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv10");
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv11");
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv12");
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv13");
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv14");
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv15");
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv16");
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv17");
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        console.log("lv18");
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv19");
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv20");
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv21");
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("lv22");
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_atSpecificTime3Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 365 days * 3;
        console.log("start");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_atSpecificTime5Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 365 days * 5;
        console.log("start");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_atSpecificTime7Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 365 days * 7;
        console.log("start");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_atSpecificTime10Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        
        uint256 timeToAdd = 365 days * 10;
        console.log("start");
        test_initialize_succeedsWithHooks_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithHooksIfInitialized_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectors_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectors_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withNative_gas_timeTest(timeToAdd); 
        vm.revertTo(snapshot);
        test_swap_succeedsWithNativeTokensIfInitialized_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_succeeds_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_againstLiqWithNative_gas_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(timeToAdd);
        vm.revertTo(snapshot);
        console.log("END");
    }
    function test_initialize_succeedsWithHooks_timeTest(uint160 sqrtPriceX96, uint256 timeToAdd) internal {
        if (!flag.beforeInitialize && !flag.afterInitialize) {
            emit log_string("Skip Test");
            return;
        }
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(currency0, currency1, IHooks(mockAddr), FEE, sqrtPriceX96);
    }

    function test_addLiquidity_succeedsWithHooksIfInitialized_timeTest(uint160 sqrtPriceX96, uint256 timeToAdd) internal {
        if (!flag.beforeAddLiquidity && !flag.afterAddLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(currency0, currency1, IHooks(mockAddr), FEE, sqrtPriceX96);

        BalanceDelta balanceDelta = modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        if (flag.beforeAddLiquidity) {
            bytes32 beforeSelector = MockHooks.beforeAddLiquidity.selector;
            bytes memory beforeParams = abi.encode(address(modifyLiquidityRouter), key, LIQUIDITY_PARAMS, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        }
        if (flag.afterAddLiquidity) {
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

    function test_removeLiquidity_succeedsWithHooksIfInitialized_timeTest(uint160 sqrtPriceX96, uint256 timeToAdd) internal {
        if (!flag.beforeRemoveLiquidity && !flag.afterRemoveLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(currency0, currency1, IHooks(mockAddr), FEE, sqrtPriceX96);
        
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        BalanceDelta balanceDelta = modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);

        if (flag.beforeRemoveLiquidity) {
            bytes32 beforeSelector = MockHooks.beforeRemoveLiquidity.selector;
            bytes memory beforeParams = abi.encode(address(modifyLiquidityRouter), key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        }
        if (flag.afterRemoveLiquidity) {
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

    function test_addLiquidity_failsWithIncorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeAddLiquidity && !flag.afterAddLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));

        if (flag.beforeAddLiquidity) {
            // Fails at beforeAddLiquidity hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        if (flag.afterAddLiquidity) {
            // Fail at afterAddLiquidity hook.
            mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        }
    }

    function test_removeLiquidity_failsWithIncorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeRemoveLiquidity && !flag.afterRemoveLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, bytes4(0xdeadbeef));

        if (flag.beforeRemoveLiquidity) {
            // Fails at beforeRemoveLiquidity hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        }
        if (flag.afterRemoveLiquidity) {
            // Fail at afterRemoveLiquidity hook.
            mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, mockHooks.beforeRemoveLiquidity.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        }
    }

    function test_addLiquidity_succeedsWithCorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeAddLiquidity && !flag.afterAddLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, mockHooks.afterAddLiquidity.selector);

        vm.expectEmit(true, true, false, true, address(manager));
        emit ModifyLiquidity(
            key.toId(),
            address(modifyLiquidityRouter),
            LIQUIDITY_PARAMS.tickLower,
            LIQUIDITY_PARAMS.tickUpper,
            LIQUIDITY_PARAMS.liquidityDelta,
            LIQUIDITY_PARAMS.salt
        );

        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_succeedsWithCorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeRemoveLiquidity && !flag.afterRemoveLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, mockHooks.beforeRemoveLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, mockHooks.afterRemoveLiquidity.selector);

        vm.expectEmit(true, true, false, true, address(manager));
        emit ModifyLiquidity(
            key.toId(),
            address(modifyLiquidityRouter),
            REMOVE_LIQUIDITY_PARAMS.tickLower,
            REMOVE_LIQUIDITY_PARAMS.tickUpper,
            REMOVE_LIQUIDITY_PARAMS.liquidityDelta,
            REMOVE_LIQUIDITY_PARAMS.salt
        );

        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_withHooks_gas_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeAddLiquidity && !flag.afterAddLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("addLiquidity with empty hook");
    }

    function test_removeLiquidity_withHooks_gas_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeRemoveLiquidity && !flag.afterRemoveLiquidity) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("removeLiquidity with empty hook");
    }

    function test_swap_succeedsWithHooksIfInitialized_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeSwap && !flag.afterSwap) {
            emit log_string("Skip Test");
            return;
        }
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        timeWarp(timeToAdd);
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(mockAddr), FEE, SQRT_PRICE_1_1);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        BalanceDelta balanceDelta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        if (flag.beforeSwap) {
            bytes32 beforeSelector = MockHooks.beforeSwap.selector;
            bytes memory beforeParams = abi.encode(address(swapRouter), key, SWAP_PARAMS, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        }
        if (flag.afterSwap) {
            bytes32 afterSelector = MockHooks.afterSwap.selector;
            bytes memory afterParams = abi.encode(address(swapRouter), key, SWAP_PARAMS, balanceDelta, ZERO_BYTES);
            assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
            assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
        }
    }

    function test_swap_failsWithIncorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeSwap && !flag.afterSwap) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_PRICE_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        if (flag.beforeSwap) {
            // Fails at beforeSwap hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        }
        if (flag.afterSwap) {
            // Fail at afterSwap hook.
            mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        }
    }

    function test_swap_succeedsWithCorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeSwap && !flag.afterSwap) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: SQRT_PRICE_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        // vm.expectEmit(true, true, true, true);
        // emit Swap(key.toId(), address(swapRouter), -10, 8, 79228162514264336880490487708, 1e18, -1, 100);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_withHooks_gas_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeSwap && !flag.afterSwap) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_4});
        testSettings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapLastCall("swap with hooks");
    }

    function test_donate_failsWithIncorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeDonate && !flag.afterDonate) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));
        
        if (flag.beforeDonate) {
            // Fails at beforeDonate hook.
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            donateRouter.donate(key, 100, 200, ZERO_BYTES);
        }
        if (flag.afterDonate) {
            // Fail at afterDonate hook.
            mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
            vm.expectRevert(Hooks.InvalidHookResponse.selector);
            donateRouter.donate(key, 100, 200, ZERO_BYTES);
        }
    }

    function test_donate_succeedsWithCorrectSelectors_timeTest(uint256 timeToAdd) internal {
        if (!flag.beforeDonate && !flag.afterDonate) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, FEE, SQRT_PRICE_1_1);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);

        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_addLiquidity_withNative_gas_timeTest(uint256 timeToAdd) internal {
        vm.breakpoint("a");
        timeWarp(timeToAdd);
        
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("addLiquidity with native token");
    }

    function test_removeLiquidity_withNative_gas_timeTest(uint256 timeToAdd) internal {
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("removeLiquidity with native token");
    }

    function test_swap_succeedsWithNativeTokensIfInitialized_timeTest(uint256 timeToAdd) internal {
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true);
        emit Swap(
            nativeKey.toId(),
            address(swapRouter),
            int128(-100),
            int128(98),
            79228162514264329749955861424,
            1e18,
            -1,
            3000
        );

        swapRouter.swap{value: 100}(nativeKey, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_swap_withNative_succeeds_timeTest(uint256 timeToAdd) internal {
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 100}(nativeKey, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_swap_withNative_gas_timeTest(uint256 timeToAdd) internal {
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        swapRouterNoChecks.swap{value: 100}(nativeKey, SWAP_PARAMS);
        snapLastCall("simple swap with native");
    }

    function test_swap_againstLiqWithNative_gas_timeTest(uint256 timeToAdd) internal {
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 1 ether}(nativeKey, SWAP_PARAMS, testSettings, ZERO_BYTES);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_4});

        swapRouter.swap{value: 1 ether}(nativeKey, params, testSettings, ZERO_BYTES);
        snapLastCall("swap against liquidity with native token");
    }

    function test_take_succeedsWithPoolWithLiquidityWithNativeToken_timeTest(uint256 timeToAdd) internal {
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);
        
        (nativeKey,) = initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, mockHooks, 3000, SQRT_PRICE_1_1, 1 ether);
        takeRouter.take{value: 1}(nativeKey, 1, 1); // assertions inside takeRouter because it takes then settles
    }

    function generateHookAddress() internal view returns (address) {
        uint160 hookFlags = 0;

        if (flag.beforeInitialize) hookFlags |= Hooks.BEFORE_INITIALIZE_FLAG;
        if (flag.afterInitialize) hookFlags |= Hooks.AFTER_INITIALIZE_FLAG;
        if (flag.beforeAddLiquidity) hookFlags |= Hooks.BEFORE_ADD_LIQUIDITY_FLAG;
        if (flag.afterAddLiquidity) hookFlags |= Hooks.AFTER_ADD_LIQUIDITY_FLAG;
        if (flag.beforeRemoveLiquidity) hookFlags |= Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;
        if (flag.afterRemoveLiquidity) hookFlags |= Hooks.AFTER_REMOVE_LIQUIDITY_FLAG;
        if (flag.beforeSwap) hookFlags |= Hooks.BEFORE_SWAP_FLAG;
        if (flag.afterSwap) hookFlags |= Hooks.AFTER_SWAP_FLAG;
        if (flag.beforeDonate) hookFlags |= Hooks.BEFORE_DONATE_FLAG;
        if (flag.afterDonate) hookFlags |= Hooks.AFTER_DONATE_FLAG;
        if (flag.beforeSwapReturnDelta) hookFlags |= Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        if (flag.afterSwapReturnDelta) hookFlags |= Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
        if (flag.afterAddLiquidityReturnDelta) hookFlags |= Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG;
        if (flag.afterRemoveLiquidityReturnDelta) hookFlags |= Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG;

        return address(uint160(hookFlags));
    }
}
