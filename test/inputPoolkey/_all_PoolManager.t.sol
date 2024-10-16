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
        if (!currency0.isAddressZero()) custom_ApproveCurrency(key.currency0, Constants.MAX_UINT256);
        custom_ApproveCurrency(key.currency1, Constants.MAX_UINT256);

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

    function test_addLiquidity_6909() public {
        // convert test tokens into ERC6909 claims
        if (currency0.isAddressZero())
            claimsRouter.deposit{value: 10_000 ether}(currency0, address(this), 10_000e18);
        else
            claimsRouter.deposit(currency0, address(this), 10_000e18);
        claimsRouter.deposit(currency1, address(this), 10_000e18);
        assertEq(manager.balanceOf(address(this), currency0.toId()), 10_000e18);
        assertEq(manager.balanceOf(address(this), currency1.toId()), 10_000e18);

        uint256 currency0BalanceBefore = currency0.balanceOfSelf();
        uint256 currency1BalanceBefore = currency1.balanceOfSelf();
        uint256 currency0PMBalanceBefore = currency0.balanceOf(address(manager));
        uint256 currency1PMBalanceBefore = currency1.balanceOf(address(manager));

        // allow liquidity router to burn our 6909 tokens
        manager.setOperator(address(modifyLiquidityRouter), true);

        // add liquidity with 6909: settleUsingBurn=true, takeClaims=true (unused)
        modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES, true, true);

        assertLt(manager.balanceOf(address(this), currency0.toId()), 10_000e18);
        assertLt(manager.balanceOf(address(this), currency1.toId()), 10_000e18);

        // ERC20s are unspent
        assertEq(currency0.balanceOfSelf(), currency0BalanceBefore);
        assertEq(currency1.balanceOfSelf(), currency1BalanceBefore);

        // PoolManager did not receive net-new ERC20s
        assertEq(currency0.balanceOf(address(manager)), currency0PMBalanceBefore);
        assertEq(currency1.balanceOf(address(manager)), currency1PMBalanceBefore);
    }

    function test_removeLiquidity_6909() public {
        if (key.currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);

        assertEq(manager.balanceOf(address(this), currency0.toId()), 0);
        assertEq(manager.balanceOf(address(this), currency1.toId()), 0);

        uint256 currency0BalanceBefore = currency0.balanceOfSelf();
        uint256 currency1BalanceBefore = currency1.balanceOfSelf();
        uint256 currency0PMBalanceBefore = currency0.balanceOf(address(manager));
        uint256 currency1PMBalanceBefore = currency1.balanceOf(address(manager));

        // remove liquidity as 6909: settleUsingBurn=true (unused), takeClaims=true
        modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES, true, true);

        assertTrue(manager.balanceOf(address(this), currency0.toId()) > 0);
        assertTrue(manager.balanceOf(address(this), currency1.toId()) > 0);

        // ERC20s are unspent
        assertEq(currency0.balanceOfSelf(), currency0BalanceBefore);
        assertEq(currency1.balanceOfSelf(), currency1BalanceBefore);

        // PoolManager did lose ERC-20s
        assertEq(currency0.balanceOf(address(manager)), currency0PMBalanceBefore);
        assertEq(currency1.balanceOf(address(manager)), currency1PMBalanceBefore);
    }

    function test_addLiquidity_secondAdditionSameRange_gas() public {
        IPoolManager.ModifyLiquidityParams memory uniqueParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -(5*key.tickSpacing), tickUpper: -(3*key.tickSpacing), liquidityDelta: 1e18, salt: 0});
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);
        snapLastCall("simple addLiquidity second addition same range");
    }

    function test_removeLiquidity_someLiquidityRemains_gas() public {
        // add double the liquidity to remove
        IPoolManager.ModifyLiquidityParams memory uniqueParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -(5*key.tickSpacing), tickUpper: -(3*key.tickSpacing), liquidityDelta: 1e18, salt: 0});
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);

        uniqueParams.liquidityDelta /= -2;
        modifyLiquidityNoChecks.modifyLiquidity(key, uniqueParams, ZERO_BYTES);
        snapLastCall("simple removeLiquidity some liquidity remains");
    }

    function test_addLiquidity_gas() public {
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("simple addLiquidity");
    }

    function test_removeLiquidity_gas() public {
        modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        snapLastCall("simple removeLiquidity");
    }

    function test_swap_succeedsIfInitialized() public {
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});
        
        if (currency0.isAddressZero())
            swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_swap_succeeds() public {
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        if (currency0.isAddressZero())
            swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_swap_gas() public {
        if (currency0.isAddressZero())
            swapRouterNoChecks.swap{value: 100}(key, SWAP_PARAMS);
        else
            swapRouterNoChecks.swap(key, SWAP_PARAMS);
        snapLastCall("simple swap");
    }

    function test_swap_mint6909IfOutputNotTaken_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        if (currency0.isAddressZero())
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        else
            swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        snapLastCall("swap mint output as 6909");
    }

    function test_swap_burn6909AsInput_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});

        if (currency0.isAddressZero()) {
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
            params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 25, sqrtPriceLimitX96: SQRT_PRICE_1_4});
        }
        else {
            swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
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
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_4});
        
        if (currency0.isAddressZero()) {
            swapRouter.swap{value: 1 ether}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);
        }
        else {
            swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        }   
        snapLastCall("swap against liquidity");
    }

    function test_swap_accruesProtocolFees(uint16 protocolFee0, uint16 protocolFee1, int256 amountSpecified) public {
        protocolFee0 = uint16(bound(protocolFee0, 0, 1000));
        protocolFee1 = uint16(bound(protocolFee1, 0, 1000));
        vm.assume(amountSpecified != 0);

        uint24 protocolFee = (uint24(protocolFee1) << 12) | uint24(protocolFee0);

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        vm.prank(address(feeController));
        manager.setProtocolFee(key, protocolFee);

        (,, slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, protocolFee);

        // Add liquidity - Fees dont accrue for positive liquidity delta.
        IPoolManager.ModifyLiquidityParams memory params = CUSTOM_LIQUIDITY_PARAMS;
        if (currency0.isAddressZero()) 
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES);
        else 
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);

        // Remove liquidity - Fees dont accrue for negative liquidity delta.
        params.liquidityDelta = -CUSTOM_LIQUIDITY_PARAMS.liquidityDelta;
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);

        // Now re-add the liquidity to test swap
        params.liquidityDelta = CUSTOM_LIQUIDITY_PARAMS.liquidityDelta;
        if (currency0.isAddressZero()) 
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES);
        else 
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams(false, amountSpecified, TickMath.MAX_SQRT_PRICE - 1);
        BalanceDelta delta;
        if (currency0.isAddressZero()) 
            delta = swapRouter.swap{value: 100}(key, swapParams, PoolSwapTest.TestSettings(false, false), ZERO_BYTES);
        else 
            delta = swapRouter.swap(key, swapParams, PoolSwapTest.TestSettings(false, false), ZERO_BYTES);
        uint256 expectedProtocolFee =
            uint256(uint128(-delta.amount1())) * protocolFee1 / ProtocolFeeLibrary.PIPS_DENOMINATOR;
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolFee);
    }

    // test successful donation if pool has liquidity
    function test_donate_succeedsWhenPoolHasLiquidity() public {
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
        donateRouter.donate(key, 0, 100, ZERO_BYTES);
        snapLastCall("donate gas with 1 token");
    }

    function test_fuzz_donate_emits_event(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 0, uint256(int256(type(int128).max)));
        amount1 = bound(amount1, 0, uint256(int256(type(int128).max)));

        vm.expectEmit(true, true, false, true, address(manager));
        emit Donate(key.toId(), address(donateRouter), uint256(amount0), uint256(amount1));
        if (currency0.isAddressZero()) {
            vm.deal(address(this), Constants.MAX_UINT256);
            donateRouter.donate{value: amount0}(key, amount0, amount1, ZERO_BYTES);
        }
        else
            donateRouter.donate(key, amount0, amount1, ZERO_BYTES);
    }

    function test_collectProtocolFees_ERC20_accumulateFees_gas() public {
        uint256 expectedFees = 10;

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        vm.prank(address(feeController));
        manager.setProtocolFee(key, MAX_PROTOCOL_FEE_BOTH_TOKENS);

        (,, slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, MAX_PROTOCOL_FEE_BOTH_TOKENS);

        if (currency0.isAddressZero())
            swapRouter.swap{value: 10000}(
                key,
                IPoolManager.SwapParams(true, -10000, SQRT_PRICE_1_2),
                PoolSwapTest.TestSettings(false, false),
                ZERO_BYTES
            );
        else
            swapRouter.swap(
                key,
                IPoolManager.SwapParams(true, -10000, SQRT_PRICE_1_2),
                PoolSwapTest.TestSettings(false, false),
                ZERO_BYTES
            );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(31337)), 0);
        vm.prank(address(feeController));
        manager.collectProtocolFees(address(31337), currency0, expectedFees);
        snapLastCall("erc20 collect protocol fees");
        assertEq(currency0.balanceOf(address(31337)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_collectProtocolFees_ERC20_accumulateFees_exactOutput() public {
        uint256 expectedFees = 10;

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        vm.prank(address(feeController));
        manager.setProtocolFee(key, MAX_PROTOCOL_FEE_BOTH_TOKENS);

        (,, slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, MAX_PROTOCOL_FEE_BOTH_TOKENS);

        if (currency0.isAddressZero())
            swapRouter.swap{value: 10000}(
                key,
                IPoolManager.SwapParams(true, -10000, SQRT_PRICE_1_2),
                PoolSwapTest.TestSettings(false, false),
                ZERO_BYTES
            );
        else
            swapRouter.swap(
                key,
                IPoolManager.SwapParams(true, -10000, SQRT_PRICE_1_2),
                PoolSwapTest.TestSettings(false, false),
                ZERO_BYTES
            );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(31337)), 0);
        vm.prank(address(feeController));
        manager.collectProtocolFees(address(31337), currency0, expectedFees);
        assertEq(currency0.balanceOf(address(31337)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_collectProtocolFees_ERC20_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint256 expectedFees = 10;

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        vm.prank(address(feeController));
        manager.setProtocolFee(key, MAX_PROTOCOL_FEE_BOTH_TOKENS);

        (,, slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, MAX_PROTOCOL_FEE_BOTH_TOKENS);

        if (currency0.isAddressZero()) {
            swapRouter.swap{value: 10000}(
                key,
                IPoolManager.SwapParams(true, -10000, SQRT_PRICE_1_2),
                PoolSwapTest.TestSettings(false, false),
                ZERO_BYTES
            );
            assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
            assertEq(manager.protocolFeesAccrued(currency1), 0);
            assertEq(currency0.balanceOf(address(31337)), 0);
            vm.prank(address(feeController));
            manager.collectProtocolFees(address(31337), currency0, 0);
            assertEq(currency0.balanceOf(address(31337)), expectedFees);
            assertEq(manager.protocolFeesAccrued(currency0), 0);
        }
        else {
            swapRouter.swap(
                key,
                IPoolManager.SwapParams(false, -10000, TickMath.MAX_SQRT_PRICE - 1),
                PoolSwapTest.TestSettings(false, false),
                ZERO_BYTES
            );
            assertEq(manager.protocolFeesAccrued(currency0), 0);
            assertEq(manager.protocolFeesAccrued(currency1), expectedFees);
            assertEq(currency1.balanceOf(address(31337)), 0);
            vm.prank(address(feeController));
            manager.collectProtocolFees(address(31337), currency1, 0);
            assertEq(currency1.balanceOf(address(31337)), expectedFees);
            assertEq(manager.protocolFeesAccrued(currency1), 0);
        }
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
}
