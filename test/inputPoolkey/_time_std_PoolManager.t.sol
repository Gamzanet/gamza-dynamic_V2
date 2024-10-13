// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";

contract PoolManagerTest is Test, Deployers, GasSnapshot {
    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_WEEK = 7 days;
    uint256 constant ONE_MONTH = 30 days;
    uint256 constant SIX_MONTHS = 180 days;
    uint256 constant ONE_YEAR = 365 days;
    uint256 constant THREE_YEAR = 365 days * 3;
    uint256 constant FIVE_YEAR = 365 days * 5;
    uint256 constant SEVEN_YEAR = 365 days * 7;
    uint256 constant TEN_YEAR = 365 days * 10;

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
    event permission(Hooks.Permissions);
    function setUp() public {
        //string memory code_json = vm.readFile("test/inputPoolkey/patched_TakeProfitsHook.json");
        string memory code_json = vm.readFile("test/inputPoolkey/patched_Allhook.json");
        address _currency0 = vm.parseJsonAddress(code_json, ".data.currency0");
        address _currency1 = vm.parseJsonAddress(code_json, ".data.currency1");
        uint24 _fee = uint24(vm.parseJsonUint(code_json, ".data.fee"));
        int24 _tickSpacing = int24(vm.parseJsonInt(code_json, ".data.tickSpacing"));
        address _hooks = vm.parseJsonAddress(code_json, ".data.hooks");

        inputkey.currency0 = Currency.wrap(_currency0);
        inputkey.currency1 = Currency.wrap(_currency1);
        inputkey.fee = (_fee < 100) ? 100 : _fee;
        inputkey.tickSpacing = _tickSpacing;
        inputkey.hooks = IHooks(_hooks);

        Hooks.Permissions memory flag;
        (bool success, bytes memory returnData) = address(inputkey.hooks).call(abi.encodeWithSignature("getHookPermissions()"));
        flag = abi.decode(returnData, (Hooks.Permissions));
        emit permission(flag);

        hookAddr = address(inputkey.hooks);
        
        // eth-sepolia
        // manager = IPoolManager(0xe8e23e97fa135823143d6b9cba9c699040d51f70);
        // swapRouter = PoolSwapTest(0x0937c4d65d7cddbf02e75b88dd33f536b201c2a6);
        // modifyLiquidityRouter = PoolModifyLiquidityTest(0x94df58ccb1ac6e5958b8ee1e2491f224414a2bf7);

        // base-sepolia
        // manager = IPoolManager(0x39BF2eFF94201cfAA471932655404F63315147a4);
        // swapRouter = PoolSwapTest(0xFf34e285F8ED393E366046153e3C16484A4dD674);
        // modifyLiquidityRouter = PoolModifyLiquidityTest(0x841B5A0b3DBc473c8A057E2391014aa4C4751351);
        vm.label(address(manager), "poolManager");
        vm.label(address(swapRouter), "swapRouter");
        vm.label(address(modifyLiquidityRouter), "modifyLiquidityRouter");
        vm.label(_hooks, "hook");
        vm.label(address(0x9eF67780BE41891AEb81db1a898A6b13Ee343fF0), "real hook");

       //deployFreshManagerAndRouters();
        
        manager = new PoolManager();
        
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        donateRouter = new PoolDonateTest(manager);

        if (!inputkey.currency0.isAddressZero()) {
            deal(address(Currency.unwrap(inputkey.currency0)), address(this), type(uint256).max);
            MockERC20(Currency.unwrap(inputkey.currency0)).approve(address(swapRouter), Constants.MAX_UINT256);
            MockERC20(Currency.unwrap(inputkey.currency0)).approve(address(modifyLiquidityRouter), Constants.MAX_UINT256);
            MockERC20(Currency.unwrap(inputkey.currency0)).approve(address(donateRouter), Constants.MAX_UINT256);
        }
        deal(address(Currency.unwrap(inputkey.currency1)), address(this), type(uint256).max);
        MockERC20(Currency.unwrap(inputkey.currency1)).approve(address(swapRouter), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(inputkey.currency1)).approve(address(modifyLiquidityRouter), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(inputkey.currency1)).approve(address(donateRouter), Constants.MAX_UINT256);
    }


    function timeWarp(uint256 timeToAdd) internal {
        uint256 currentTime = vm.getBlockTimestamp();
        vm.warp(currentTime + timeToAdd);
        uint256 newTime = vm.getBlockTimestamp();
        assertEq(newTime, uint256(currentTime + timeToAdd ), "Time did not warp correctly");
        console.log("warp end");
        
    }

    function test_initialize_atSpecificTime1Day(uint160 sqrtPriceX96) public {
        // uint256[] memory timeIntervals = new uint256[](9);
        // timeIntervals[0] = ONE_DAY;
        // timeIntervals[1] = ONE_WEEK;
        // timeIntervals[2] = ONE_MONTH;
        // timeIntervals[3] = SIX_MONTHS;
        // timeIntervals[4] = ONE_YEAR;
        // timeIntervals[5] = THREE_YEAR;
        // timeIntervals[6] = FIVE_YEAR;
        // timeIntervals[7] = SEVEN_YEAR;
        // timeIntervals[8] = TEN_YEAR;
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        //vm.snapshot();이 미래에 deprecate 된다고 함. 이후 vm.snapshotState()로 변경해야 함. 현재 버전에선 X
        uint256 snapshot = vm.snapshot(); 
        //for (uint i = 0; i < timeIntervals.length; i++) {
            // vm.revertTo(); deprecate -> bool status = vm.revertToState(state);
        vm.revertTo(snapshot);
        uint256 timeToAdd = 1 days;
        //test_initialize_succeedsWithHooks(sqrtPriceX96, timeToAdd);
        console.log("start");
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 1");
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 2");
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 3");
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 4");
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 5");
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 6");
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 7");
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 8");
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 9");
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 10");
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 11");
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 12");
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 13");
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        console.log("level 14");
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        console.log("END");
        //}
    }
    function test_initialize_atSpecificTime1Week(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 7 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
    function test_initialize_atSpecificTime1Month(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 30 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
        function test_initialize_atSpecificTime6Month(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 30 days * 6;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
    function test_initialize_atSpecificTime1Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 365 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
    function test_initialize_atSpecificTime3Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 3 * 365 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
        function test_initialize_atSpecificTime5Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 5 * 365 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
        function test_initialize_atSpecificTime7Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 7 * 365 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
    function test_initialize_atSpecificTime10Year(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uint256 snapshot = vm.snapshot(); 
        vm.revertTo(snapshot);
        uint256 timeToAdd = 10 * 365 days;
        test_swap_succeedsWithHooksIfInitializedUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_initialize_succeedsWithHooksUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(sqrtPriceX96, timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_addLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_removeLiquidity_withHooks_gasUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_swap_withHooks_gasUsingTimeUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_failsWithIncorrectSelectorsUsingTime(timeToAdd);
        vm.revertTo(snapshot);
        test_donate_succeedsWithCorrectSelectorsUsingTime(timeToAdd);
    }
    /////////// time mimnimum test
    function test_swap_succeedsWithHooksIfInitializedUsingTime(uint256 timeToAdd) internal {

        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);

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

    

    function test_initialize_succeedsWithHooksUsingTime(uint160 sqrtPriceX96, uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_INITIALIZE_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_INITIALIZE_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));

        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(mockAddr), inputkey.fee, inputkey.tickSpacing, sqrtPriceX96);
    }



    function test_addLiquidity_succeedsWithHooksIfInitializedUsingTime(uint160 sqrtPriceX96, uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_removeLiquidity_succeedsWithHooksIfInitializedUsingTime(uint160 sqrtPriceX96, uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);

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

    function test_addLiquidity_failsWithIncorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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
            else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);        
        }
    }

    function test_removeLiquidity_failsWithIncorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_addLiquidity_succeedsWithCorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_removeLiquidity_succeedsWithCorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_addLiquidity_withHooks_gasUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
        address payable mockAddr = payable(address(uint160(address(hookAddr)) ^ (0xffffffff << 128)));
        MockHooks impl = new MockHooks();
        vm.etch(mockAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(mockAddr);

        (key,) = initPool(inputkey.currency0, inputkey.currency1, mockHooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1);

        if (currency0.isAddressZero()) modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        else modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("addLiquidity with hook");
    }

    function test_removeLiquidity_withHooks_gasUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    
    function test_swap_failsWithIncorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_swap_succeedsWithCorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_swap_withHooks_gasUsingTimeUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_donate_failsWithIncorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_DONATE_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_DONATE_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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

    function test_donate_succeedsWithCorrectSelectorsUsingTime(uint256 timeToAdd) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_DONATE_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_DONATE_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        timeWarp(timeToAdd);
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
}
