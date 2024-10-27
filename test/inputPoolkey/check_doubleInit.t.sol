// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolEmptyUnlockTest} from "v4-core/src/test/PoolEmptyUnlockTest.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Vm} from "forge-std/Vm.sol";
import {setupContract} from "./setupContract.sol";

contract DoubleInitHookTest is Test, setupContract {
    using Hooks for IHooks;
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    function setUp() public {
        setupPoolkey();
    }

    function test_double_init() public {
        PoolKey memory other_key = key;
        other_key.tickSpacing = key.tickSpacing + 1;
        vm.prank(deployer);
        
        vm.startStateDiffRecording();
        manager.initialize(other_key, SQRT_PRICE_1_1, ZERO_BYTES);
        Vm.AccountAccess[] memory records1 = vm.stopAndReturnStateDiff();
        
        for(uint256 i = 0;i < records1.length ; i ++){
            for(uint256 j = 0; j < records1[i].storageAccesses.length; j++){


                if(records1[i].storageAccesses[j].isWrite == true){
                    console.log("slot-write-0");
                    console.logBytes32(records1[i].storageAccesses[j].slot);
                    console.logBytes32(records1[i].storageAccesses[j].previousValue);
                    console.logBytes32(records1[i].storageAccesses[j].newValue);
                    console.logAddress(records1[i].storageAccesses[j].account);
                    console.logAddress(records1[i].account);
                }
                // console.log("diff start");
                // console.log("i ; ",i);
                // console.log("j ; ",j);
                // console.logBytes32(records1[i].storageAccesses[j].slot);
                // console.logBool(records1[i].storageAccesses[j].isWrite);

                
                
            }
        }

        other_key.tickSpacing = other_key.tickSpacing + 1;
        vm.startStateDiffRecording();
        manager.initialize(other_key, SQRT_PRICE_1_1, ZERO_BYTES);
        Vm.AccountAccess[] memory records2 = vm.stopAndReturnStateDiff();
        console.log("record 2 ");
        for(uint256 i = 0;i < records2.length ; i ++){
            for(uint256 j = 0; j < records2[i].storageAccesses.length; j++){

                if(records2[i].storageAccesses[j].isWrite == true){
                    console.log("slot-write-1");
                    console.logBytes32(records2[i].storageAccesses[j].slot);
                    console.logBytes32(records2[i].storageAccesses[j].previousValue);
                    console.logBytes32(records2[i].storageAccesses[j].newValue);
                    console.logAddress(records2[i].storageAccesses[j].account);
                    console.logAddress(records2[i].account);
                    
                }
                // console.log("diff start");
                // console.log("i ; ",i);
                // console.log("j ; ",j);
                // console.logBool(records2[i].storageAccesses[j].isWrite);

                
                
            }
        }
        /*
        try  {
            revert("Double initialization enabled in the hook");
        }catch {}
        */
    }
}