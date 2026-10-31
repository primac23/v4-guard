// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {CircuitBreakerHook} from "../src/hooks/CircuitBreakerHook.sol";

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

contract CircuitBreakerVsSingleTxAttack is Test, Deployers, IFlashBorrower {
    using PoolIdLibrary for PoolKey;

    uint24 internal constant MAX_MOVE = 50;
    uint256 internal constant FLASH_AMOUNT = 1e18;

    IERC20 internal token0;
    IERC20 internal token1;
    CircuitBreakerHook internal hook;
    PoolKey internal cbKey;
    VulnerableSpotLending internal market;
    FlashLender internal lender;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        token0 = IERC20(Currency.unwrap(currency0));
        token1 = IERC20(Currency.unwrap(currency1));

        address hookAddr = address(
            uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144)
        );
        deployCodeTo("CircuitBreakerHook.sol:CircuitBreakerHook", abi.encode(manager), hookAddr);
        hook = CircuitBreakerHook(hookAddr);

        cbKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hookAddr));
        hook.configure(
            cbKey, CircuitBreakerHook.Config({maxTickMove: MAX_MOVE, windowSeconds: 300, cooldownSeconds: 3600})
        );
        manager.initialize(cbKey, SQRT_PRICE_1_1);

        ModifyLiquidityParams memory p = LIQUIDITY_PARAMS;
        p.tickLower = TickMath.minUsableTick(60);
        p.tickUpper = TickMath.maxUsableTick(60);
        p.liquidityDelta = int256(1e18);
        modifyLiquidityRouter.modifyLiquidity(cbKey, p, ZERO_BYTES);

        market = new VulnerableSpotLending(manager, cbKey.toId(), token0, token1);
        token1.transfer(address(market), 10e18);
        lender = new FlashLender();
        token1.transfer(address(lender), 100e18);
    }

    function onFlash(address, uint256 amount) external override {
        require(msg.sender == address(lender), "only lender");
        uint256 t0Before = token0.balanceOf(address(this));
        swap(cbKey, false, -int256(amount), ZERO_BYTES);
        uint256 collateral = token0.balanceOf(address(this)) - t0Before;
        token0.approve(address(market), collateral);
        market.deposit(collateral);
        uint256 b = market.maxBorrow(address(this));
        uint256 available = token1.balanceOf(address(market));
        market.borrow(b < available ? b : available);
        require(token1.transfer(address(lender), amount), "repay");
    }

    function runAttack(uint256 amount) external returns (int256 profit, uint256 badDebt) {
        uint256 before = token1.balanceOf(address(this));
        lender.flash(token1, amount);
        uint256 afterBal = token1.balanceOf(address(this));
        profit = afterBal >= before ? int256(afterBal - before) : -int256(before - afterBal);
        uint256 debt = market.debtOf(address(this));
        uint256 coll = market.collateralOf(address(this));
        badDebt = debt > coll ? debt - coll : 0;
    }

    function test_SingleTxAttack_SucceedsDespiteBreaker() public {
        (int256 profit, uint256 badDebt) = this.runAttack(FLASH_AMOUNT);
        bool halted = hook.isHalted(cbKey.toId());
        console.log("CMP_PROFIT", uint256(profit));
        console.log("CMP_BADDEBT", badDebt);
        console.log("CMP_HALTED", halted ? 1 : 0);
        assertGt(profit, 0, "attack profitable");
        assertGt(badDebt, 0, "bad debt left");
        assertTrue(halted, "pool halted after the fact");
    }

    function test_HonestTrader_BlockedAfterAttack() public {
        this.runAttack(FLASH_AMOUNT);
        vm.expectRevert();
        swap(cbKey, true, -1e14, ZERO_BYTES);
    }
}
