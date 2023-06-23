// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "../src/UniswapV3Pool.sol";


contract UniswapV3PoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool transferInCallback = true;
    bool transferLessAmount0 = false;
    bool transferLessAmount1 = false;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool transferInCallback;
        bool mintLiqudity;
    }

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    function setupTestCase(
        TestCaseParams memory params
    ) internal returns (uint256 poolBalance0, uint256 poolBalance1) {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );

        if (params.mintLiqudity) {
            (poolBalance0, poolBalance1) = pool.mint(
                address(this),
                params.lowerTick,
                params.upperTick,
                params.liquidity
            );
        }

        transferInCallback = params.transferInCallback;
    }

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInCallback: true,
            mintLiqudity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = 0.99897661834742528 ether;
        uint256 expectedAmount1 = 5000 ether;
        assertEq(
            poolBalance0,
            expectedAmount0,
            "incorrect token0 deposited amount"
        );
        assertEq(
            poolBalance1,
            expectedAmount1,
            "incorrect token1 deposited amount"
        );
        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.lowerTick, params.upperTick)
        );
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(
            params.lowerTick
        );
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5602277097478614198912276234240,
            "invalid current sqrtP"
        );
        assertEq(tick, 85176, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
    }

    function test_RevertWhen_MintTooLargeUpperTick() public {
        int24 tooLargeTick = 887272 + 1;
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            5602277097478614198912276234240,
            85176
        );

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(
            address(this),
            84222,
            tooLargeTick,
            1517882343751509868544
        );
    }

    function test_RevertWhen_MintTooSmallLowerTick() public {
        int24 tooSmallTick = -887272 - 1;
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            5602277097478614198912276234240,
            85176
        );

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(
            address(this),
            tooSmallTick,
            86129,
            1517882343751509868544
        );
    }

    function test_RevertWhen_UpperTick_Equal_LowerTick() public {
        int24 tick = 86129;
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            5602277097478614198912276234240,
            85176
        );

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(
            address(this),
            tick,
            tick,
            1517882343751509868544
        );
    }

    function test_RevertWhen_UpperTick_Lower_LowerTick() public {
        int24 tick = 86129;
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            5602277097478614198912276234240,
            85176
        );

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(
            address(this),
            tick,
            tick - 1,
            1517882343751509868544
        );
    }

    function test_RevertWhen_ZeroAmount() public {
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            5602277097478614198912276234240,
            85176
        );

        vm.expectRevert(UniswapV3Pool.ZeroLiquidity.selector);
        pool.mint(
            address(this),
            84222,
            86129,
            0
        );
    }

    function test_RevertWhen_InsufficientToken0Transfer() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInCallback: false,
            mintLiqudity: false
        });

        setupTestCase(params);
        transferLessAmount0 = true;

        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            params.liquidity
        );
    }

    function test_RevertWhen_InsufficientToken1Transfer() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInCallback: false,
            mintLiqudity: false
        });

        setupTestCase(params);
        transferLessAmount1 = true;

        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            params.liquidity
        );
    }


    function test_RevertWhen_InsufficientToken0() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 0.5 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInCallback: true,
            mintLiqudity: false
        });

        setupTestCase(params);

        vm.expectRevert(stdError.arithmeticError);
        pool.mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            params.liquidity
        );
    }

    function test_RevertWhen_InsufficientToken1() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 4999 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInCallback: true,
            mintLiqudity: false
        });

        setupTestCase(params);

        vm.expectRevert(stdError.arithmeticError);
        pool.mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            params.liquidity
        );
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1) public {
        if (transferInCallback) {
            token0.transfer(msg.sender, amount0);
            token1.transfer(msg.sender, amount1);
        }else if (transferLessAmount0) {
            token0.transfer(msg.sender, amount0 - 1);
            token1.transfer(msg.sender, amount1);
        }else if (transferLessAmount1) {
            token0.transfer(msg.sender, amount0);
            token1.transfer(msg.sender, amount1 - 1);
        }
    }
}
