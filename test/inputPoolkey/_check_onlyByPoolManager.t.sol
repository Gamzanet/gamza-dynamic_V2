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
    IHooks hook;
    Hooks.Permissions perms;
    IPoolManager.SwapParams params = IPoolManager.SwapParams({
        zeroForOne: true,
        amountSpecified: -0.00001 ether,
        sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    });

    BalanceDelta balanceDelta = BalanceDeltaLibrary.ZERO_DELTA;
    function setUp() public {
        //string memory code_json = vm.readFile("test/inputPoolkey/patched_TakeProfitsHook.json");
        //string memory code_json = vm.readFile("test/inputPoolkey/badOnlyByPoolManager.json");
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
        hook = IHooks(hookAddr);

    }

    function test_beforeRemoveLiquidity() public {
        if (perms.beforeRemoveLiquidity) {
            try hook.beforeRemoveLiquidity(address(this), key, 
                IPoolManager.ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 0 ether,
                    salt: bytes32(0)
                }), ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeRemoveLiquidity must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_afterRemoveLiquidity() public {
        if (perms.afterRemoveLiquidity) {
            
            try hook.afterRemoveLiquidity(address(this), key, 
                IPoolManager.ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 0 ether,
                    salt: bytes32(0)
                }),balanceDelta,balanceDelta, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterRemoveLiquidity must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_beforeAddLiquidity() public {
        if (perms.beforeAddLiquidity) {
            try hook.beforeAddLiquidity(address(this), key, 
                IPoolManager.ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 0 ether,
                    salt: bytes32(0)
                }), ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeAddLiquidity must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_afterAddLiquidity() public {
        if (perms.afterAddLiquidity) {
            try hook.afterAddLiquidity(address(this), key, 
                IPoolManager.ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 0 ether,
                    salt: bytes32(0)
                }),balanceDelta,balanceDelta, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterAddLiquidity must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_beforeSwap() public {
        if (perms.beforeSwap) {
            try hook.beforeSwap(address(this), key, params, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeSwap must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_afterSwap() public {
        if (perms.afterSwap) {
            try hook.afterSwap(address(this), key, params, BalanceDeltaLibrary.ZERO_DELTA, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterSwap must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_afterInitialize() public {
        if (perms.afterInitialize) {
            try hook.afterInitialize(address(this), key, SQRT_PRICE_1_1, 0, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterInitialize must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_beforeInitialize() public {
        if (perms.beforeInitialize) {
            try hook.beforeInitialize(address(this), key, SQRT_PRICE_1_1, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeInitialize must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_beforeDonate() public {
        if (perms.beforeDonate) {
            try hook.beforeDonate(address(this), key, 0, 0, ZERO_BYTES) {
                revert("Expected NotPoolManager : beforeDonate must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    function test_afterDonate() public {
        if (perms.afterDonate) {
            try hook.afterDonate(address(this), key, 0, 0, ZERO_BYTES) {
                revert("Expected NotPoolManager : afterDonate must be called only by PoolManager");
            } catch  {
                // assertEq(reason, "NotPoolManager");
            }
        }
    }

    event permission(Hooks.Permissions);

    function checkFlag() public {
        (,bytes memory returnData) = address(inputkey.hooks).call(abi.encodeWithSignature("getHookPermissions()"));
        perms = abi.decode(returnData, (Hooks.Permissions));
        emit permission(perms);
    }


}
