// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ImbalanceGateHook} from "../src/ImbalanceGateHook.sol";

contract MockPoolManager {
    bool private locked;

    function unlock(bytes calldata data) external returns (bytes memory result) {
        require(!locked, "Already locked");
        locked = true;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        locked = false;
    }

    function dispatchAfterSwap(
        address hookAddress,
        PoolKey calldata key,
        BalanceDelta delta
    ) external returns (bytes4, int128) {
        IPoolManager.SwapParams memory emptyParams;
        return IHooks(hookAddress).afterSwap(msg.sender, key, emptyParams, delta, "");
    }
}

contract GuardedUnlockRouter is IUnlockCallback {
    MockPoolManager public immutable manager;
    ImbalanceGateHook public immutable hook;

    struct SwapSimulation {
        int128 delta0;
        int128 delta1;
    }

    constructor(MockPoolManager _manager, ImbalanceGateHook _hook) {
        manager = _manager;
        hook = _hook;
    }

    function executeSwaps(PoolKey calldata key, SwapSimulation[] calldata swaps) external {
        manager.unlock(abi.encode(key, swaps));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(manager), "Not manager");
        (PoolKey memory key, SwapSimulation[] memory swaps) = abi.decode(data, (PoolKey, SwapSimulation[]));

        for (uint256 i = 0; i < swaps.length; i++) {
            BalanceDelta delta = toBalanceDelta(swaps[i].delta0, swaps[i].delta1);
            manager.dispatchAfterSwap(address(hook), key, delta);
        }

        hook.validateSettlementInvariant(key);

        return "";
    }
}

contract ImbalanceGateHookTest is Test {
    using PoolIdLibrary for PoolKey;

    MockPoolManager internal manager;
    ImbalanceGateHook internal hook;
    GuardedUnlockRouter internal router;
    PoolKey internal key;

    uint256 internal constant EPSILON0 = 1000;
    uint256 internal constant EPSILON1 = 1000;

    function setUp() public {
        manager = new MockPoolManager();

        address hookAddress = address(uint160(Hooks.AFTER_SWAP_FLAG));

        ImbalanceGateHook impl = new ImbalanceGateHook(
            IPoolManager(address(manager)),
            EPSILON0,
            EPSILON1
        );
        vm.etch(hookAddress, address(impl).code);
        hook = ImbalanceGateHook(hookAddress);

        router = new GuardedUnlockRouter(manager, hook);

        key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });
    }

    function test_BenignSingleSwap_Passes() public {
        GuardedUnlockRouter.SwapSimulation[] memory swaps = new GuardedUnlockRouter.SwapSimulation[](1);
        swaps[0] = GuardedUnlockRouter.SwapSimulation({delta0: 500, delta1: -450});

        router.executeSwaps(key, swaps);

        (int256 cum0, int256 cum1) = hook.getAccumulatedDeltas(key.toId());
        assertEq(cum0, 0);
        assertEq(cum1, 0);
    }

    function test_CompensatedMultiSwap_Passes() public {
        GuardedUnlockRouter.SwapSimulation[] memory swaps = new GuardedUnlockRouter.SwapSimulation[](2);
        swaps[0] = GuardedUnlockRouter.SwapSimulation({delta0: 1500, delta1: -1400});
        swaps[1] = GuardedUnlockRouter.SwapSimulation({delta0: -800, delta1: 700});

        router.executeSwaps(key, swaps);
    }

    function test_CumulativeDeltaExceedsThreshold_Reverts() public {
        GuardedUnlockRouter.SwapSimulation[] memory swaps = new GuardedUnlockRouter.SwapSimulation[](1);
        swaps[0] = GuardedUnlockRouter.SwapSimulation({delta0: 1001, delta1: -500});

        vm.expectRevert(
            abi.encodeWithSelector(
                ImbalanceGateHook.MaxImbalanceExceeded.selector,
                key.toId(),
                int256(1001),
                int256(-500)
            )
        );
        router.executeSwaps(key, swaps);
    }

    function test_ExactThreshold_Passes() public {
        GuardedUnlockRouter.SwapSimulation[] memory swaps = new GuardedUnlockRouter.SwapSimulation[](1);
        swaps[0] = GuardedUnlockRouter.SwapSimulation({delta0: int128(int256(EPSILON0)), delta1: -int128(int256(EPSILON1))});

        router.executeSwaps(key, swaps);
    }

    function test_ThresholdPlusOne_Reverts() public {
        GuardedUnlockRouter.SwapSimulation[] memory swaps = new GuardedUnlockRouter.SwapSimulation[](1);
        swaps[0] = GuardedUnlockRouter.SwapSimulation({
            delta0: int128(int256(EPSILON0 + 1)), 
            delta1: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ImbalanceGateHook.MaxImbalanceExceeded.selector,
                key.toId(),
                int256(EPSILON0 + 1),
                int256(0)
            )
        );
        router.executeSwaps(key, swaps);
    }

    function test_FailedToxicSwap_DoesNotCorruptSubsequentSwap() public {
        GuardedUnlockRouter.SwapSimulation[] memory toxic = new GuardedUnlockRouter.SwapSimulation[](1);
        toxic[0] = GuardedUnlockRouter.SwapSimulation({delta0: 5000, delta1: -5000});

        vm.expectRevert();
        router.executeSwaps(key, toxic);

        GuardedUnlockRouter.SwapSimulation[] memory benign = new GuardedUnlockRouter.SwapSimulation[](1);
        benign[0] = GuardedUnlockRouter.SwapSimulation({delta0: 200, delta1: -190});

        router.executeSwaps(key, benign);
    }

    function testFuzz_SettlementInvariantHolds(int64 d0_1, int64 d0_2) public {
        int256 net0 = int256(d0_1) + int256(d0_2);

        GuardedUnlockRouter.SwapSimulation[] memory swaps = new GuardedUnlockRouter.SwapSimulation[](2);
        swaps[0] = GuardedUnlockRouter.SwapSimulation({delta0: int128(d0_1), delta1: 0});
        swaps[1] = GuardedUnlockRouter.SwapSimulation({delta0: int128(d0_2), delta1: 0});

        uint256 absNet0 = net0 < 0 ? uint256(-net0) : uint256(net0);

        if (absNet0 > EPSILON0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ImbalanceGateHook.MaxImbalanceExceeded.selector,
                    key.toId(),
                    net0,
                    int256(0)
                )
            );
            router.executeSwaps(key, swaps);
        } else {
            router.executeSwaps(key, swaps);
        }
    }
}
