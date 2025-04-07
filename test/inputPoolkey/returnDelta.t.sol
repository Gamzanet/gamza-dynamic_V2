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
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {setupContract} from "./setupContract.sol";

// Routers
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {Action, PoolNestedActionsTest} from "v4-core/src/test/PoolNestedActionsTest.sol";
import {Actions, ActionsRouter} from "v4-core/src/test/ActionsRouter.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract returnDeltaTest is Test, Deployers, setupContract {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    function setUp() public {
        setupPoolkey();
        vm.startPrank(txOrigin, txOrigin);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
        else
            modifyLiquidityRouter.modifyLiquidity(key, CUSTOM_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        IPoolManager.ModifyLiquidityParams memory params = 
            custom_seedMoreLiquidity(key, 1 ether, 1 ether);

        snap_balance();
        {
            BalanceDelta delta;
            if (currency0.isAddressZero())
                delta = modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES, false, false);
            else
                delta = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);
            log_delta(delta, "addLiquidity");
        }
        log_balance("addLiquidity");
    }

    function test_removeLiquidity_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        IPoolManager.ModifyLiquidityParams memory params = 
            custom_seedMoreLiquidity(key, 1 ether, 1 ether);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES, false, false);
        else
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);
            
        snap_balance();
        {
            params.liquidityDelta = -params.liquidityDelta;
            BalanceDelta delta;
            delta = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);
            log_delta(delta, "removeLiquidity");
        }
        log_balance("removeLiquidity");
    }

    function test_addLiquidity6909_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        IPoolManager.ModifyLiquidityParams memory params = 
            custom_seedMoreLiquidity(key, 1 ether, 1 ether);

        if (currency0.isAddressZero())
            claimsRouter.deposit{value: 10 ether}(currency0, txOrigin, 10 ether);
        else
            claimsRouter.deposit(currency0, txOrigin, 10 ether);
        claimsRouter.deposit(currency1, txOrigin, 10 ether);
        manager.setOperator(address(modifyLiquidityRouter), true);

        snap_balance();
        {
            BalanceDelta delta;
            if (currency0.isAddressZero())
                delta = modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES, true, false);
            else
                delta = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, true, false);
            log_delta(delta, "addLiquidity6909");
        }
        log_balance("addLiquidity6909");
    }

    function test_removeLiquidity6909_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        IPoolManager.ModifyLiquidityParams memory params = 
            custom_seedMoreLiquidity(key, 1 ether, 1 ether);
        if (currency0.isAddressZero())
            modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(key, params, ZERO_BYTES, false, false);
        else
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, false);
            
        snap_balance();
        {
            params.liquidityDelta = -params.liquidityDelta;
            BalanceDelta delta;
            delta = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES, false, true);
            log_delta(delta, "removeLiquidity6909");
        }
        log_balance("removeLiquidity6909");
    }

    function test_swap_exactOut_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SWAP_PARAMS.amountSpecified = 100-1;
        snap_balance();
        {
            BalanceDelta delta;
            _logForExpectedPrice("SWAP-exactOut");
            if (currency0.isAddressZero())
                delta = swapRouter.swap{value: 1 ether}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            else
                delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            log_delta(delta, "SWAP-exactOut");
        }
        log_balance("SWAP-exactOut");
    }

    function test_swap_exactOut_Mint6909_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});
        SWAP_PARAMS.amountSpecified = 100-1;
        snap_balance();
        {
            BalanceDelta delta;
            _logForExpectedPrice("SWAP-exactOut Mint 6909");
            if (currency0.isAddressZero())
                delta = swapRouter.swap{value: 1 ether}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            else
                delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            log_delta(delta, "SWAP-exactOut Mint 6909");
        }
        log_balance("SWAP-exactOut Mint 6909");
    }

    function test_swap_exactOut_Burn6909_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);   
        if (currency0.isAddressZero())
            claimsRouter.deposit{value: 10 ether}(currency0, txOrigin, 10 ether);
        else
            claimsRouter.deposit(currency0, txOrigin, 10 ether);
        claimsRouter.deposit(currency1, txOrigin, 10 ether);
        manager.setOperator(address(swapRouter), true);
        
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: true});
        SWAP_PARAMS.amountSpecified = 100-1;
        snap_balance();
        {
            BalanceDelta delta;
            _logForExpectedPrice("SWAP-exactOut Burn 6909");
            if (currency0.isAddressZero())
                delta = swapRouter.swap{value: 1 ether}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            else
                delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            log_delta(delta, "SWAP-exactOut Burn 6909");
        }
        log_balance("SWAP-exactOut Burn 6909");
    }

    function test_swap_exactIn_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
            
        snap_balance();
        {
            BalanceDelta delta;
            _logForExpectedPrice("SWAP-exactIn");
            if (currency0.isAddressZero()) {
                delta = swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            }
            else
                delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            log_delta(delta, "SWAP-exactIn");
        }
        log_balance("SWAP-exactIn");
    }

    function test_swap_exactIn_Mint6909_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});
            
        snap_balance();
        {
            BalanceDelta delta;
            _logForExpectedPrice("SWAP-exactIn Mint 6909");
            if (currency0.isAddressZero())
                delta = swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            else
                delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            log_delta(delta, "SWAP-exactIn Mint 6909");
        }
        log_balance("SWAP-exactIn Mint 6909");
    }

    function test_swap_exactIn_Burn6909_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);   
        if (currency0.isAddressZero())
            claimsRouter.deposit{value: 10 ether}(currency0, txOrigin, 10 ether);
        else
            claimsRouter.deposit(currency0, txOrigin, 10 ether);
        claimsRouter.deposit(currency1, txOrigin, 10 ether);
        manager.setOperator(address(swapRouter), true);
        
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: true});
        snap_balance();
        {
            BalanceDelta delta;
             _logForExpectedPrice("SWAP-exactIn Burn 6909");
            if (currency0.isAddressZero())
                delta = swapRouter.swap{value: 100}(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            else
                delta = swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
            log_delta(delta, "SWAP-exactIn Burn 6909");
        }
        log_balance("SWAP-exactIn Burn 6909");
    }

    function test_donate_return_delta() public {
        vm.startPrank(txOrigin, txOrigin);
        snap_balance();
        {
            BalanceDelta delta;
            if (currency0.isAddressZero())
                delta = donateRouter.donate{value: 100}(key, 100, 100, ZERO_BYTES);
            else
                delta = donateRouter.donate(key, 100, 100, ZERO_BYTES);
            log_delta(delta, "Donate");
        }
        log_balance("Donate");
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

    function log_delta(BalanceDelta delta, string memory str) internal {
        uint256 totalLength = 40; // 전체 라인의 길이 (중앙의 문자열 포함)
        uint256 strLength = bytes(str).length + 6;
        uint256 starCount = (totalLength - strLength) / 2; // 좌우 별의 개수

        // 좌우 별을 맞추기 위해 공백을 고려한 정렬
        string memory leftStars = _repeat("*", starCount);
        string memory rightStars = _repeat("*", totalLength - starCount - strLength);

        string memory amount0 = string(abi.encodePacked(str,"-amount0 delta:"));
        string memory amount1 = string(abi.encodePacked(str,"-amount1 delta:"));

        console.log();
        console.log(string(abi.encodePacked(leftStars, " ", str, " DELTA", " ", rightStars)));
        console.log(amount0, delta.amount0());
        console.log(amount1, delta.amount1());
        console.log(_repeat("*", totalLength + 2));
        console.log();
    }

    struct UsersBalance {
        uint256 managerBalance0;
        uint256 managerBalance1;
        
        uint256 hookBalance0;
        uint256 hookBalance1;

        uint256 userBalance0;
        uint256 userBalance1;

        uint256 hook6909Balance0;
        uint256 hook6909Balance1;
        
        uint256 user6909Balance0;
        uint256 user6909Balance1;
    }
    UsersBalance userBalance;
    function snap_balance() internal {
        userBalance.managerBalance0 = currency0.balanceOf(address(manager));
        userBalance.managerBalance1 = currency1.balanceOf(address(manager));

        userBalance.hookBalance0 = currency0.balanceOf(address(key.hooks));
        userBalance.hookBalance1 = currency1.balanceOf(address(key.hooks));

        userBalance.userBalance0 = currency0.balanceOf(address(txOrigin));
        userBalance.userBalance1 = currency1.balanceOf(address(txOrigin));

        userBalance.hook6909Balance0 = manager.balanceOf(address(key.hooks), currency0.toId());
        userBalance.hook6909Balance1 = manager.balanceOf(address(key.hooks), currency1.toId());

        userBalance.user6909Balance0 = manager.balanceOf(address(txOrigin), currency0.toId());
        userBalance.user6909Balance1 = manager.balanceOf(address(txOrigin), currency1.toId());
    }

    function log_balance(string memory str) internal view {
        uint256 totalLength = 50; // 전체 라인의 길이 (중앙의 문자열 포함)
        uint256 strLength = bytes(str).length + 13;
        uint256 starCount = (totalLength - strLength) / 2; // 좌우 별의 개수

        // 좌우 별을 맞추기 위해 공백을 고려한 정렬
        string memory leftStars = _repeat("*", starCount);
        string memory rightStars = _repeat("*", totalLength - starCount - strLength);

        string memory managerAmount0 = string(abi.encodePacked(str,"-managerAmount0 delta:"));
        string memory managerAmount1 = string(abi.encodePacked(str,"-managerAmount1 delta:"));
        string memory hookAmount0 = string(abi.encodePacked(str,"-hookAmount0 delta:"));
        string memory hookAmount1 = string(abi.encodePacked(str,"-hookAmount1 delta:"));
        string memory userAmount0 = string(abi.encodePacked(str,"-userAmount0 delta:"));
        string memory userAmount1 = string(abi.encodePacked(str,"-userAmount1 delta:"));
        string memory hook6909Amount0 = string(abi.encodePacked(str,"-hook6909Amount0 delta:"));
        string memory hook6909Amount1 = string(abi.encodePacked(str,"-hook6909Amount1 delta:"));
        string memory user6909Amount0 = string(abi.encodePacked(str,"-user6909Amount0 delta:"));
        string memory user6909Amount1 = string(abi.encodePacked(str,"-user6909Amount1 delta:"));

        console.log();
        console.log(string(abi.encodePacked(leftStars, " ", str, " Balance DELTA", " ", rightStars)));
        console.log(managerAmount0, - int(userBalance.managerBalance0) + int(currency0.balanceOf(address(manager))));
        console.log(managerAmount1, - int(userBalance.managerBalance1) + int(currency1.balanceOf(address(manager))));
        console.log(hookAmount0, - int(userBalance.hookBalance0) + int(currency0.balanceOf(address(key.hooks))));
        console.log(hookAmount1, - int(userBalance.hookBalance1) + int(currency1.balanceOf(address(key.hooks))));
        console.log(userAmount0, - int(userBalance.userBalance0) + int(currency0.balanceOf(address(txOrigin))));
        console.log(userAmount1, - int(userBalance.userBalance1) + int(currency1.balanceOf(address(txOrigin))));
        console.log(hook6909Amount0, - int(userBalance.hook6909Balance0) + int(manager.balanceOf(address(key.hooks), currency0.toId())));
        console.log(hook6909Amount1, - int(userBalance.hook6909Balance1) + int(manager.balanceOf(address(key.hooks), currency1.toId())));
        console.log(user6909Amount0, - int(userBalance.user6909Balance0) + int(manager.balanceOf(address(txOrigin), currency0.toId())));
        console.log(user6909Amount1, - int(userBalance.user6909Balance1) + int(manager.balanceOf(address(txOrigin), currency1.toId())));
        console.log(_repeat("*", totalLength + 2));
        console.log();
    }

    // 별 반복 생성 함수
    function _repeat(string memory s, uint256 times) internal pure returns (string memory) {
        string memory result = "";
        for (uint256 i = 0; i < times; i++) {
            result = string(abi.encodePacked(result, s));
        }
        return result;
    }
    function _logForExpectedPrice(string memory s) internal {

        (uint256 _liquidity) = manager.getLiquidity(key.toId());
        (uint160 _priceCurrent, int24 _tick, uint24 _protocolFee, uint24 _lpFee) = manager.getSlot0(key.toId());
        // string[] memory inputs = new string[](7);
        // inputs[0] = "python3";
        // inputs[1] = "test/inputPoolkey/utils/getSwapPrice.py";
        // inputs[2] = Strings.toString(_priceCurrent);
        // inputs[3] = Strings.toString(_liquidity);
        // inputs[4] = Strings.toString(uint256(SWAP_PARAMS.amountSpecified < 0 ? -SWAP_PARAMS.amountSpecified : SWAP_PARAMS.amountSpecified));
        // inputs[5] = Strings.toString(key.fee);

        // bytes memory res = vm.ffi(inputs);
        // console.log(string(res));
        console.log(string.concat(s, "-for-expected-current-price: "), _priceCurrent);
        console.log(string.concat(s, "-for-expected-current-liquidity: "), _liquidity);
        console.log(string.concat(s, "-for-expected-amount0-specified: "), SWAP_PARAMS.amountSpecified < 0 ? -SWAP_PARAMS.amountSpecified : SWAP_PARAMS.amountSpecified);
        console.log(string.concat(s, "-for-expected-current-fee: "), _lpFee);
    }

    function _logForActualSwapPrice(string memory s, int128 _amount_in, int128 _amount_out) internal {

        // string[] memory inputs = new string[](5);
        // inputs[0] = "python3";
        // inputs[1] = "test/inputPoolkey/utils/getSwapPrice.py";
        // inputs[2] = Strings.toString(uint128(_amount_in < 0 ? -_amount_in : _amount_in));    #amount0 delta:
        // inputs[3] = Strings.toString(uint128(_amount_out < 0 ? -_amount_out : _amount_out)); #amount1 delta:

        // bytes memory res = vm.ffi(inputs);
        // console.log(string(res));
        
    }
}
