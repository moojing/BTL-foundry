// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {BitLuck} from "../src/BitLuck.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function factory() external pure returns (address);
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

contract BitLuckV2ForkTest is Test {
    BitLuck public bitluck;
    IERC20 public usdt;
    IUniswapV2Router02 public router;
    IUniswapV2Factory public factory;

    // BSC Testnet addresses - Official PancakeSwap V2 from documentation
    address constant PANCAKE_ROUTER_V2 =
        0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    /**
     * @dev 使用 USDT 地址作為 USD1 的測試代理
     *
     * USD1 架構說明：
     * - USD1 採用可升級代理模式 (Proxy + Implementation)
     * - 具有 freeze/unfreeze 和 pause/unpause 管理功能
     * - 支持 ERC20Permit 和所有權管理
     *
     * 測試策略：
     * 1. BitLuck 核心功能主要依賴標準 ERC20 接口
     * 2. USDT 提供相同的基礎 ERC20 功能（18位小數，轉帳等）
     * 3. 在測試環境中，不需要模擬 USD1 的管理功能（freeze/pause）
     * 4. 主網部署時，此地址將替換為 USD1 的 Proxy 合約地址
     *
     * 注意：BitLuck 合約透過標準 ERC20 接口與 USD1 互動，
     *      因此不會受到 USD1 升級機制的直接影響
     */
    address constant USDT_TOKEN = 0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684; // USDT as USD1 proxy for testing
    address constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

    address public deployer;
    address public user1;
    address public user2;
    address public lpProvider;

    function setUp() public {
        // Fork BSC testnet using environment variable
        string memory rpcUrl = vm.envOr(
            "BSC_TESTNET_RPC_URL",
            string("https://bsc-testnet.public.blastapi.io")
        );
        vm.createSelectFork(rpcUrl);

        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        lpProvider = makeAddr("lpProvider");

        // Fund accounts with BNB for gas
        vm.deal(deployer, 10 ether);
        vm.deal(user1, 5 ether);
        vm.deal(user2, 5 ether);
        vm.deal(lpProvider, 10 ether);

        // Setup contracts
        usdt = IERC20(USDT_TOKEN);
        router = IUniswapV2Router02(PANCAKE_ROUTER_V2);
        factory = IUniswapV2Factory(router.factory());

        // Fund accounts with USDT tokens
        deal(USDT_TOKEN, deployer, 10000 * 10 ** 18);
        deal(USDT_TOKEN, lpProvider, 10000 * 10 ** 18);
        deal(USDT_TOKEN, user1, 1000 * 10 ** 18);
        deal(USDT_TOKEN, user2, 1000 * 10 ** 18);

        // Deploy BitLuck
        vm.startPrank(deployer);
        bitluck = new BitLuck(USDT_TOKEN, PANCAKE_ROUTER_V2);

        // Distribute BTL tokens
        uint256 deployerBalance = bitluck.balanceOf(deployer);
        bitluck.transfer(user1, (deployerBalance * 1) / 100); // 1%
        bitluck.transfer(user2, (deployerBalance * 1) / 100); // 1%
        bitluck.transfer(lpProvider, (deployerBalance * 10) / 100); // 10%

        vm.stopPrank();

        console.log("=== BitLuck V2 Fork Test Setup ===");
        console.log("BitLuck deployed at:", address(bitluck));
        console.log("Using PancakeSwap V2 Router:", PANCAKE_ROUTER_V2);
        console.log("Using USDT token:", USDT_TOKEN);
        console.log("Deployer BTL balance:", bitluck.balanceOf(deployer));
        console.log("LP Provider BTL balance:", bitluck.balanceOf(lpProvider));
    }

    function testV2RouterDeployment() public view {
        assertEq(bitluck.name(), "BitLuck");
        assertEq(bitluck.symbol(), "BTL");
        assertEq(bitluck._USD1(), USDT_TOKEN);
        assertEq(bitluck.RouterAddress(), PANCAKE_ROUTER_V2);
        assertTrue(bitluck.balanceOf(deployer) > 0);
        console.log("V2 Router deployment test passed");
    }

    function testCreatePairAndAddLiquidity() public {
        // First enable trading as deployer
        vm.prank(deployer);
        bitluck.openTrading();

        vm.startPrank(lpProvider);

        uint256 btlAmount = bitluck.balanceOf(lpProvider);
        uint256 usdtAmount = 1000 * 10 ** 18; // 1k USDT

        console.log("=== Creating Pair and Adding Liquidity ===");
        console.log("BTL Amount for LP:", btlAmount);
        console.log("USDT Amount for LP:", usdtAmount);

        // Check if pair exists, create if not
        address pair = factory.getPair(address(bitluck), USDT_TOKEN);
        if (pair == address(0)) {
            pair = factory.createPair(address(bitluck), USDT_TOKEN);
            console.log("Created new pair at:", pair);
        }

        // Approve tokens
        bitluck.approve(PANCAKE_ROUTER_V2, btlAmount);
        usdt.approve(PANCAKE_ROUTER_V2, usdtAmount);

        console.log("Approved tokens for router");

        // Add liquidity
        (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
            address(bitluck),
            USDT_TOKEN,
            btlAmount,
            usdtAmount,
            0, // Accept any amount of tokens
            0, // Accept any amount of tokens
            lpProvider,
            block.timestamp + 300
        );

        console.log("Liquidity added successfully:");
        console.log("- BTL added:", amountA);
        console.log("- USDT added:", amountB);
        console.log("- LP tokens received:", liquidity);

        // Verify pair exists and has liquidity
        assertTrue(pair != address(0));
        assertTrue(liquidity > 0);

        vm.stopPrank();
    }

    function testStakingFunctionality() public {
        vm.startPrank(user1);

        uint256 stakeAmount = bitluck.balanceOf(user1) / 2;
        uint256 balanceBefore = bitluck.balanceOf(user1);

        console.log("=== Testing Staking ===");
        console.log("User1 balance before:", balanceBefore);
        console.log("Staking amount:", stakeAmount);

        bitluck.stakeBTL(stakeAmount, address(0));

        uint256 balanceAfter = bitluck.balanceOf(user1);
        uint256 stakedAmount = bitluck.stakedBTL(user1);

        console.log("User1 balance after:", balanceAfter);
        console.log("Staked amount:", stakedAmount);

        assertEq(stakedAmount, stakeAmount);
        assertEq(balanceAfter, balanceBefore - stakeAmount);
        assertTrue(bitluck.hasDeposited(user1));

        vm.stopPrank();
    }

    function testReferralSystem() public {
        address referrer = makeAddr("referrer");
        vm.prank(deployer);
        bitluck.transfer(referrer, 1000000 * 10 ** 9);

        vm.startPrank(user2);

        uint256 stakeAmount = bitluck.balanceOf(user2) / 2;
        uint256 referrerBalanceBefore = bitluck.balanceOf(referrer);

        console.log("=== Testing Referral System ===");
        console.log("Stake amount:", stakeAmount);
        console.log("Referrer balance before:", referrerBalanceBefore);

        bitluck.stakeBTL(stakeAmount, referrer);

        uint256 referrerBalanceAfter = bitluck.balanceOf(referrer);
        uint256 bonus = referrerBalanceAfter - referrerBalanceBefore;
        uint256 expectedBonus = (stakeAmount * 1000) / 10000; // 10%

        console.log("Referrer balance after:", referrerBalanceAfter);
        console.log("Actual bonus:", bonus);
        console.log("Expected bonus:", expectedBonus);

        assertEq(bonus, expectedBonus);

        vm.stopPrank();
    }

    function testTradingEnabled() public {
        // Enable trading first
        vm.prank(deployer);
        bitluck.openTrading();

        console.log("=== Testing Trading ===");
        console.log("Trading enabled at block:", bitluck.startTradeBlock());
        assertTrue(bitluck.startTradeBlock() > 0);

        // Test a small transfer should work
        vm.prank(user1);
        bitluck.transfer(user2, 1000);

        console.log("Transfer successful after trading enabled");
    }

    function testContractConfiguration() public view {
        console.log("=== Contract Configuration ===");
        console.log("Buy USDT Fee:", bitluck._buyUSD1Fee(), "basis points");
        console.log(
            "Buy Marketing Fee:",
            bitluck._buyMarketingFee(),
            "basis points"
        );
        console.log("Sell USDT Fee:", bitluck._sellUSD1Fee(), "basis points");
        console.log(
            "Sell Marketing Fee:",
            bitluck._sellMarketingFee(),
            "basis points"
        );
        console.log(
            "Referral Bonus:",
            bitluck.REFERRAL_BONUS(),
            "basis points"
        );
        console.log("Holder Condition:", bitluck.holderCondition());
        console.log("Draw Interval:", bitluck.drawIntervalBlocks(), "blocks");

        // Verify fee structure matches PRD
        assertEq(bitluck._buyUSD1Fee(), 300); // 3%
        assertEq(bitluck._buyMarketingFee(), 100); // 1%
        assertEq(bitluck._sellUSD1Fee(), 300); // 3%
        assertEq(bitluck._sellMarketingFee(), 100); // 1%
        assertEq(bitluck.REFERRAL_BONUS(), 1000); // 10%
    }
}
