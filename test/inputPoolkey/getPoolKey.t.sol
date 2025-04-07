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

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";

contract setupContract is Test {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using SafeCast for *;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    PositionManager manager;

    function test_getPoolkey() public {
        string memory directory = vm.envString("_data_location"); // ../../src/data
        string memory dataPath = vm.envString("_targetPoolKey"); // asdf.json
        string memory filePath = string.concat(directory, dataPath);
        string memory code_json = vm.readFile(filePath);

        bytes32 poolid_json = vm.parseJsonBytes32(code_json, ".data.poolid");
        // bytes32 poolid = PoolId.wrap(poolid_json);
        bytes25 poolkey = bytes25(poolid_json);
        setPositionManager();

        // check initialized
        (
            Currency currency0,
            Currency currency1,
            uint24 fee,
            int24 tickSpacing,
            IHooks hooks
        ) = manager.poolKeys(poolkey);

        console.log("currency0:", Currency.unwrap(currency0));
        console.log("currency1:", Currency.unwrap(currency1));
        console.log("fee:", fee);
        console.log("tickSpacing:", tickSpacing);
        console.log("hooks:", address(hooks));
    }

    function setPositionManager() internal {
        if (block.chainid == 130) {
            // Unichain
            manager = PositionManager(payable(0x4529A01c7A0410167c5740C487A8DE60232617bf));
        } else if (block.chainid == 1) {
            // Ethereum Mainnet
            manager = PositionManager(payable(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e));
        } else if (block.chainid == 8453) {
            // Base Mainnet
            manager = PositionManager(payable(0x7C5f5A4bBd8fD63184577525326123B519429bDc));
        } else if (block.chainid == 42161) {
            // Arbitrum One
            manager = PositionManager(payable(0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869));
        } else {
            revert("Unsupported chain");
        }
    }
}
