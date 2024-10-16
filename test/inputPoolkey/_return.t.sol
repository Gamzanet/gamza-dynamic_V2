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
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

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

    IPoolManager.ModifyLiquidityParams public CUSTOM_LIQUIDITY_PARAMS;
    IPoolManager.ModifyLiquidityParams public CUSTOM_REMOVE_LIQUIDITY_PARAMS;
    IPoolManager.SwapParams public CUSTOM_SWAP_PARAMS;

    function setUp() public {
        string memory code_json = vm.readFile("test/inputPoolkey/Allhook.json");

        address _currency0 = vm.parseJsonAddress(code_json, ".data.currency0");
        address _currency1 = vm.parseJsonAddress(code_json, ".data.currency1");
        uint24 _fee = uint24(vm.parseJsonUint(code_json, ".data.fee"));
        int24 _tickSpacing = int24(vm.parseJsonInt(code_json, ".data.tickSpacing"));
        address _hooks = vm.parseJsonAddress(code_json, ".data.hooks");

        key.currency0 = Currency.wrap(_currency0);
        key.currency1 = Currency.wrap(_currency1);
        key.fee = _fee;
        key.tickSpacing = _tickSpacing;
        key.hooks = IHooks(_hooks);
        (currency0, currency1) = (key.currency0, key.currency1);

        CUSTOM_LIQUIDITY_PARAMS = IPoolManager.ModifyLiquidityParams({tickLower: -(2*_tickSpacing), tickUpper: (2*_tickSpacing), liquidityDelta: 1e18, salt: 0});
        CUSTOM_REMOVE_LIQUIDITY_PARAMS = IPoolManager.ModifyLiquidityParams({tickLower: -(2*_tickSpacing), tickUpper: (2*_tickSpacing), liquidityDelta: -1e18, salt: 0});

        custom_deployFreshManagerAndRouters();
        if (!currency0.isAddressZero()) custom_ApproveCurrency(key.currency0, 10_000 ether);
        custom_ApproveCurrency(key.currency1, 10_000 ether);

        // check initialized
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(key.toId());
        if (sqrtPriceX96 == 0) {
            initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, SQRT_PRICE_1_1, ZERO_BYTES);
            sqrtPriceX96 = SQRT_PRICE_1_1;
        }

        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_return_delta() public {
        IPoolManager.ModifyLiquidityParams memory params = 
            custom_seedMoreLiquidity(key, 1 ether, 1 ether);

        BalanceDelta delta;
        if (currency0.isAddressZero())
            delta = modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES, false, false);
        else
            delta = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);

        console.log();
        console.log("******** addLiquidity DELTA *********");
        console.log("amount0 delta:", delta.amount0());
        console.log("amount1 delta:", delta.amount1());
        console.log("*************************************");
        console.log();
    }

    function test_removeLiquidity_return_delta() public {
        IPoolManager.ModifyLiquidityParams memory params = 
            custom_seedMoreLiquidity(key, 1 ether, 1 ether);

        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES, false, false);
        else
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);
        
        params.liquidityDelta = -params.liquidityDelta;
        BalanceDelta delta;
        delta = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);

        console.log();
        console.log("******* removeLiquidity DELTA *******");
        console.log("amount0 delta:", delta.amount0());
        console.log("amount1 delta:", delta.amount1());
        console.log("*************************************");
        console.log();
    }

    function test_swap_return_delta() public {
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        BalanceDelta delta;
        if (currency0.isAddressZero())
            delta = swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        else
            delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        console.log();
        console.log("************ SWAP DELTA *************");
        console.log("amount0 delta:", delta.amount0());
        console.log("amount1 delta:", delta.amount1());
        console.log("*************************************");
        console.log();
    }

    function test_donate_return_delta() public {
        BalanceDelta delta;
        if (currency0.isAddressZero())
            delta = donateRouter.donate{value: 100}(key, 100, 100, ZERO_BYTES);
        else
            delta = donateRouter.donate(key, 100, 100, ZERO_BYTES);

        console.log();
        console.log("*********** Donate DELTA ************");
        console.log("amount0 delta:", delta.amount0());
        console.log("amount1 delta:", delta.amount1());
        console.log("*************************************");
        console.log();
    }

    function custom_deployFreshManagerAndRouters() internal {
        // unichain-sepolia
        manager = IPoolManager(0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967);

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

        vm.prank(0x762a34656662F1ecbC033D8c6b34B77E4eA435B7); // manager owner
        manager.setProtocolFeeController(feeController);
    }

    function custom_ApproveCurrency(Currency currency, uint256 amount) internal {
        MockERC20 token = MockERC20(Currency.unwrap(currency));
        
        deal(address(token), address(this), amount);
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
            token.approve(toApprove[i], amount);
        }
    }

    function custom_seedMoreLiquidity(PoolKey memory _key, uint256 amount0, uint256 amount1) 
        internal view
        returns (IPoolManager.ModifyLiquidityParams memory params)
    {
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(_key.toId());
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(CUSTOM_LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(CUSTOM_LIQUIDITY_PARAMS.tickUpper),
            amount0,
            amount1
        );

        params = IPoolManager.ModifyLiquidityParams({
            tickLower: CUSTOM_LIQUIDITY_PARAMS.tickLower,
            tickUpper: CUSTOM_LIQUIDITY_PARAMS.tickUpper,
            liquidityDelta: int128(liquidityDelta),
            salt: 0
        });
    }
}
