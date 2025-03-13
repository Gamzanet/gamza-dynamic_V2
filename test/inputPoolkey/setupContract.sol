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
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";

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
import {Actions, ActionsRouter} from "v4-core/src/test/ActionsRouter.sol";

contract setupContract is Test, Deployers {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

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

    event Donate(
        PoolId indexed id,
        address indexed sender,
        uint256 amount0,
        uint256 amount1
    );

    event Transfer(
        address caller,
        address indexed sender,
        address indexed receiver,
        uint256 indexed id,
        uint256 amount
    );

    IPoolManager.ModifyLiquidityParams public CUSTOM_LIQUIDITY_PARAMS;
    IPoolManager.ModifyLiquidityParams public CUSTOM_REMOVE_LIQUIDITY_PARAMS;
    IPoolManager.SwapParams public CUSTOM_SWAP_PARAMS;

    address txOrigin = makeAddr("Alice");
    address deployer;
    function setupPoolkey() public {
        string memory directory = vm.envString("_data_location"); // ../../src/data
        string memory dataPath = vm.envString("_targetPoolKey"); // asdf.json
        string memory filePath = string.concat(directory, dataPath);
        string memory code_json = vm.readFile(filePath);

        address _currency0 = vm.parseJsonAddress(code_json, ".data.currency0");
        address _currency1 = vm.parseJsonAddress(code_json, ".data.currency1");
        uint24 _fee = uint24(vm.parseJsonUint(code_json, ".data.fee"));
        int24 _tickSpacing = int24(
            vm.parseJsonInt(code_json, ".data.tickSpacing")
        );
        address _hooks = vm.parseJsonAddress(code_json, ".data.hooks");

        deployer = vm.parseJsonAddress(code_json, ".deployer");

        key.currency0 = Currency.wrap(_currency0);
        key.currency1 = Currency.wrap(_currency1);
        key.fee = _fee;
        key.tickSpacing = _tickSpacing;
        key.hooks = IHooks(_hooks);
        (currency0, currency1) = (key.currency0, key.currency1);

        CUSTOM_LIQUIDITY_PARAMS = IPoolManager.ModifyLiquidityParams({
            tickLower: -(2 * _tickSpacing),
            tickUpper: (2 * _tickSpacing),
            liquidityDelta: 1 ether,
            salt: 0
        });
        CUSTOM_REMOVE_LIQUIDITY_PARAMS = IPoolManager.ModifyLiquidityParams({
            tickLower: -(2 * _tickSpacing),
            tickUpper: (2 * _tickSpacing),
            liquidityDelta: -1 ether,
            salt: 0
        });
        CUSTOM_SWAP_PARAMS = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        custom_deployFreshManagerAndRouters();
        vm.startPrank(txOrigin, txOrigin);
        {
            vm.deal(txOrigin, Constants.MAX_UINT128 / 2);
            if (!currency0.isAddressZero())
                custom_ApproveCurrency(
                    key.currency0,
                    Constants.MAX_UINT128 / 2
                );
            custom_ApproveCurrency(key.currency1, Constants.MAX_UINT128 / 2);
        }
        vm.stopPrank();

        // check initialized
        (uint160 sqrtPriceX96, , , ) = manager.getSlot0(key.toId());
        if (sqrtPriceX96 == 0) {
            vm.prank(deployer);
            initPool(
                key.currency0,
                key.currency1,
                key.hooks,
                key.fee,
                key.tickSpacing,
                SQRT_PRICE_1_1
            );
            sqrtPriceX96 = SQRT_PRICE_1_1;
        }
    }

    function custom_deployFreshManagerAndRouters() internal {
        if (block.chainid == 130) {
            // Unichain
            manager = IPoolManager(0x1F98400000000000000000000000000000000004);
        } else if (block.chainid == 1) {
            // Ethereum Mainnet
            manager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
        } else if (block.chainid == 8453) {
            // Base Mainnet
            manager = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);
        } else if (block.chainid == 42161) {
            // Arbitrum One
            manager = IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        }
        else {
            revert("Unsupported chain");
        }

        swapRouter = new PoolSwapTest(manager);
        swapRouterNoChecks = new SwapRouterNoChecks(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        claimsRouter = new PoolClaimsTest(manager);
        nestedActionRouter = new PoolNestedActionsTest(manager);
        actionsRouter = new ActionsRouter(manager);
    }

    function custom_ApproveCurrency(
        Currency currency,
        uint256 amount
    ) internal {
        MockERC20 token = MockERC20(Currency.unwrap(currency));

        deal(address(token), txOrigin, amount);
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
