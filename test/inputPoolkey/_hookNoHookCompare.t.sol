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
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {AmountHelpers} from "v4-core/test/utils/AmountHelpers.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IQuoter} from "v4-periphery/src/interfaces/IQuoter.sol";
import {Quoter} from "v4-periphery/src/lens/Quoter.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";


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
    using PoolIdLibrary for PoolKey;
    PoolKey inputkey;
    PoolKey emptyHook;
    address hookAddr;
    Quoter quoter;
    IPoolManager.ModifyLiquidityParams public CUSTOM_LIQUIDITY_PARAMS;
    IPoolManager.ModifyLiquidityParams public CUSTOM_REMOVE_LIQUIDITY_PARAMS;
    IPoolManager.SwapParams public CUSTOM_SWAP_PARAMS =
        IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_2});

    function setUp() public {
        console.log("setup start :",gasleft());
        string memory directory = vm.envString("_data_location"); // ../../src/data
        string memory dataPath = vm.envString("_targetPoolKey"); // asdf.json
        string memory filePath = string.concat(directory, dataPath);
        string memory code_json = vm.readFile(filePath);

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
        
        CUSTOM_LIQUIDITY_PARAMS = IPoolManager.ModifyLiquidityParams({tickLower: -(2*_tickSpacing), tickUpper: (2*_tickSpacing), liquidityDelta: 1e18, salt: 0});
        CUSTOM_REMOVE_LIQUIDITY_PARAMS = IPoolManager.ModifyLiquidityParams({tickLower: -(2*_tickSpacing), tickUpper: (2*_tickSpacing), liquidityDelta: -1e18, salt: 0});
        custom_deployFreshManagerAndRouters();
        if (!inputkey.currency0.isAddressZero()) custom_ApproveCurrency(inputkey.currency0);
        custom_ApproveCurrency(inputkey.currency1);

        // check initialized
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(inputkey.toId());
        if (sqrtPriceX96 == 0) {
            initPool(inputkey.currency0, inputkey.currency1, inputkey.hooks, inputkey.fee, inputkey.tickSpacing, SQRT_PRICE_1_1, ZERO_BYTES);
            sqrtPriceX96 = SQRT_PRICE_1_1;
        }

        key = inputkey;
        (emptyHook,) = initPool(inputkey.currency0, inputkey.currency1, IHooks(address(0)), inputkey.fee, inputkey.tickSpacing, sqrtPriceX96, ZERO_BYTES);
        console.log("setup end:",gasleft());
    }

    function test_addLiquidity_compare() public{
        uint256 snapshot = vm.snapshot();
        test_addLiquidity(inputkey);
        vm.revertTo(snapshot);
        test_addLiquidity(emptyHook);
        vm.revertTo(snapshot);
    }

    function test_addLiquidity(PoolKey memory keys) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_ADD_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        uint256 start;
        uint256 end;
        if (keys.currency0.isAddressZero()) {

            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, LIQUIDITY_PARAMS, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();
            
        }
        else {
            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            modifyLiquidityRouter.modifyLiquidity(keys, LIQUIDITY_PARAMS, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();

            
        }
        if( address(keys.hooks) == address(0x0) ){
            console.log("no-hook-add-gas-using : ", start - end);
        }
        else{
            console.log("hook-add-gas-using : ", start - end);
        }
        

    }
    function test_removeLiquidity_compare() public{
        uint256 snapshot = vm.snapshot();      
        test_removeLiquidity(inputkey);
        vm.revertTo(snapshot);
        test_removeLiquidity(emptyHook);
        vm.revertTo(snapshot);

    }
    function test_removeLiquidity(PoolKey memory keys) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        uint256 start;
        uint256 end;
        if (keys.currency0.isAddressZero()) {
            
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, LIQUIDITY_PARAMS, ZERO_BYTES);

            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            modifyLiquidityRouter.modifyLiquidity(keys, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();

            
        }
        else {
            modifyLiquidityRouter.modifyLiquidity(keys, LIQUIDITY_PARAMS, ZERO_BYTES);

            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            modifyLiquidityRouter.modifyLiquidity(keys, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();

        }
        if( address(keys.hooks) == address(0x0) ){
            console.log("no-hook-remove-gas-using : ", start - end);
        }
        else{
            console.log("hook-remove-gas-using : ", start - end);
        }
        
    }
    function test_donate_compare() public{
        uint256 snapshot = vm.snapshot();
        test_donate(inputkey);
        vm.revertTo(snapshot);
        test_donate(emptyHook);
    }
    function test_donate(PoolKey memory keys) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        uint256 start;
        uint256 end;
        if (keys.currency0.isAddressZero()){
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, LIQUIDITY_PARAMS, ZERO_BYTES);

            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            donateRouter.donate{value: 100}(keys, 100, 200, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();
            
        }
        else{
            modifyLiquidityRouter.modifyLiquidity(keys, LIQUIDITY_PARAMS, ZERO_BYTES);

            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            donateRouter.donate(keys, 100, 200, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();
            
        }

        if( address(keys.hooks) == address(0x0) ){
            console.log("no-hook-donate-gas-using : ", start - end);
        }
        else{
            console.log("hook-doante-gas-using : ", start - end);
        }

    }

    function test_swap_compare() public{
        console.log(gasleft());
        uint256 snapshot = vm.snapshot();      
        test_swap(inputkey);
        vm.revertTo(snapshot);
        test_swap(emptyHook);
        vm.revertTo(snapshot);
    }

    function test_swap(PoolKey memory keys) internal {
        if (
            !Hooks.hasPermission(inputkey.hooks, Hooks.BEFORE_SWAP_FLAG) &&
            !Hooks.hasPermission(inputkey.hooks, Hooks.AFTER_SWAP_FLAG)
        ) {
            emit log_string("Skip Test");
            return;
        }
        uint256 start;
        uint256 end;
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        BalanceDelta balance;
        if (inputkey.currency0.isAddressZero()){
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(keys, LIQUIDITY_PARAMS, ZERO_BYTES);


            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            balance = swapRouter.swap{value: 100}(keys, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();

        } 
        else{
            modifyLiquidityRouter.modifyLiquidity(keys, LIQUIDITY_PARAMS, ZERO_BYTES);

            vm.pauseGasMetering();
            start = gasleft();
            vm.resumeGasMetering();
            balance = swapRouter.swap(keys, CUSTOM_SWAP_PARAMS, testSettings, ZERO_BYTES);
            vm.pauseGasMetering();
            end = gasleft();
            vm.resumeGasMetering();

        }

        (uint160 sqrtPrice,int24 tick,uint24 protocolFee,uint24 lpFee ) = manager.getSlot0(keys.toId());
        if(address(keys.hooks) == address(0x0)){
            
            console.log("no-hook-Swap-protocolFee-using : ", protocolFee);
            console.log("no-hook-Swap-lpFee-using : ", lpFee);
            console.log("no-hook-Swap-balance-amount0-using : ",balance.amount0());
            console.log("no-hook-Swap-balance-amount1-using : ",balance.amount1());
            console.log("no-hook-swap-gas-using : ", start - end);
        }
        else{
            console.log("hook-Swap-protocolFee-using : ", protocolFee);
            console.log("hook-Swap-lpFee-using : ", lpFee);
            console.log("hook-Swap-balance-amount0-using : ",balance.amount0());
            console.log("hook-Swap-balance-amount1-using : ",balance.amount1());
            console.log("hook-swap-gas-using : ", start - end);
        }
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

        quoter = new Quoter(IPoolManager(manager));
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
