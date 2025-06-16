// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {BitLuck} from "../src/BitLuck.sol";
import {MockUSDT} from "../src/MockUSDT.sol";

contract MockRouter {
    struct Factory {
        address factory;
    }

    Factory public factoryInfo;

    constructor() {
        factoryInfo.factory = address(new MockFactory());
    }

    function factory() external view returns (address) {
        return factoryInfo.factory;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint,
        uint,
        address[] calldata,
        address,
        uint
    ) external {}
}

contract MockFactory {
    function createPair(address, address) external returns (address) {
        return address(0x1234567890123456789012345678901234567890); // Mock pair address
    }
}

contract BitLuckTest is Test {
    BitLuck public bitluck;
    MockUSDT public usdt;
    MockRouter public router;

    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public referrer;

    uint256 public constant INITIAL_BTL_SUPPLY = 1000000000000 * 10 ** 9; // 1 trillion BTL
    uint256 public constant STAKE_AMOUNT = 1000000000 * 10 ** 9; // 1 billion BTL
    uint256 public constant MIN_HOLDER_AMOUNT = 1000000000 * 10 ** 9; // 0.1% minimum holding

    event BTLStaked(address indexed user, uint256 amount);
    event BTLUnstaked(address indexed user, uint256 amount);
    event BTLRewardClaimed(address indexed user, uint256 amount);
    event USD1DividendDistributed(address indexed user, uint256 amount);
    event USD1LotteryWon(address indexed winner, uint256 amount);
    event ReferralBonusPaid(
        address indexed referrer,
        address indexed referred,
        uint256 amount
    );
    event ReferralSet(address indexed user, address indexed referrer);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        referrer = makeAddr("referrer");

        // Deploy mock contracts
        usdt = new MockUSDT();
        router = new MockRouter();

        // Deploy BitLuck with mock addresses
        bitluck = new BitLuck(address(usdt), address(router));

        // Distribute BTL tokens for testing
        bitluck.transfer(user1, STAKE_AMOUNT * 10);
        bitluck.transfer(user2, STAKE_AMOUNT * 10);
        bitluck.transfer(user3, STAKE_AMOUNT * 10);
        bitluck.transfer(referrer, STAKE_AMOUNT * 10);

        // Provide USDT to contract for rewards
        usdt.mint(address(bitluck), 1000000 * 10 ** 18); // 1M USDT
    }

    function testInitialState() public view {
        assertEq(bitluck.name(), "BitLuck");
        assertEq(bitluck.symbol(), "BTL");
        assertEq(bitluck.decimals(), 9);
        assertEq(bitluck.totalSupply(), INITIAL_BTL_SUPPLY);
        assertEq(bitluck.totalStakedBTL(), 0);
        assertEq(bitluck.holderCondition(), MIN_HOLDER_AMOUNT);
    }

    function testStakingWithoutReferrer() public {
        vm.startPrank(user1);

        uint256 balanceBefore = bitluck.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit BTLStaked(user1, STAKE_AMOUNT);

        bitluck.stakeBTL(STAKE_AMOUNT, address(0));

        assertEq(bitluck.stakedBTL(user1), STAKE_AMOUNT);
        assertEq(bitluck.totalStakedBTL(), STAKE_AMOUNT);
        assertEq(bitluck.balanceOf(user1), balanceBefore - STAKE_AMOUNT);
        assertTrue(bitluck.hasDeposited(user1));

        vm.stopPrank();
    }

    function testStakingWithReferrer() public {
        vm.startPrank(user1);

        uint256 balanceBefore = bitluck.balanceOf(user1);
        uint256 referrerBalanceBefore = bitluck.balanceOf(referrer);
        uint256 expectedReferralBonus = (STAKE_AMOUNT * 1000) / 10000; // 10%
        uint256 expectedStakeAmount = STAKE_AMOUNT - expectedReferralBonus;

        vm.expectEmit(true, true, false, true);
        emit ReferralSet(user1, referrer);

        vm.expectEmit(true, true, false, true);
        emit ReferralBonusPaid(referrer, user1, expectedReferralBonus);

        vm.expectEmit(true, false, false, true);
        emit BTLStaked(user1, expectedStakeAmount);

        bitluck.stakeBTL(STAKE_AMOUNT, referrer);

        assertEq(bitluck.stakedBTL(user1), expectedStakeAmount);
        assertEq(bitluck.balanceOf(user1), balanceBefore - STAKE_AMOUNT);
        assertEq(
            bitluck.balanceOf(referrer),
            referrerBalanceBefore + expectedReferralBonus
        );
        assertEq(bitluck.referralEarnings(referrer), expectedReferralBonus);

        (address userReferrer, uint256 earnings, bool hasDeposited_) = bitluck
            .getReferralInfo(user1);
        assertEq(userReferrer, referrer);
        assertEq(earnings, 0); // user1 doesn't have referral earnings
        assertTrue(hasDeposited_);

        vm.stopPrank();
    }

    function testSecondStakeNoReferralBonus() public {
        // First stake with referrer
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, referrer);

        uint256 referrerBalanceAfterFirst = bitluck.balanceOf(referrer);

        // Second stake should not give referral bonus
        vm.startPrank(user1);

        uint256 balanceBefore = bitluck.balanceOf(user1);

        bitluck.stakeBTL(STAKE_AMOUNT, referrer);

        assertEq(
            bitluck.stakedBTL(user1),
            (STAKE_AMOUNT * 90) / 100 + STAKE_AMOUNT
        ); // 90% from first + 100% from second
        assertEq(bitluck.balanceOf(user1), balanceBefore - STAKE_AMOUNT);
        assertEq(bitluck.balanceOf(referrer), referrerBalanceAfterFirst); // No additional bonus

        vm.stopPrank();
    }

    function testUnstaking() public {
        // First stake some BTL
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, address(0));

        vm.startPrank(user1);

        uint256 stakedBefore = bitluck.stakedBTL(user1);
        uint256 balanceBefore = bitluck.balanceOf(user1);
        uint256 unstakeAmount = STAKE_AMOUNT / 2;

        vm.expectEmit(true, false, false, true);
        emit BTLUnstaked(user1, unstakeAmount);

        bitluck.unstakeBTL(unstakeAmount);

        assertEq(bitluck.stakedBTL(user1), stakedBefore - unstakeAmount);
        assertEq(bitluck.balanceOf(user1), balanceBefore + unstakeAmount);
        assertEq(bitluck.totalStakedBTL(), stakedBefore - unstakeAmount);

        vm.stopPrank();
    }

    function testCannotUnstakeMoreThanStaked() public {
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, address(0));

        vm.startPrank(user1);

        vm.expectRevert("Insufficient staked BTL");
        bitluck.unstakeBTL(STAKE_AMOUNT + 1);

        vm.stopPrank();
    }

    function testCannotStakeZeroAmount() public {
        vm.startPrank(user1);

        vm.expectRevert("Amount must be greater than 0");
        bitluck.stakeBTL(0, address(0));

        vm.stopPrank();
    }

    function testCannotStakeMoreThanBalance() public {
        vm.startPrank(user1);

        uint256 balance = bitluck.balanceOf(user1);

        vm.expectRevert("Insufficient BTL balance");
        bitluck.stakeBTL(balance + 1, address(0));

        vm.stopPrank();
    }

    function testGetUserStakingInfo() public {
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, address(0));

        (
            uint256 stakedAmount,
            uint256 pendingBTLRewards,
            uint256 pendingUSD1Dividends
        ) = bitluck.getUserStakingInfo(user1);

        assertEq(stakedAmount, STAKE_AMOUNT);
        assertEq(pendingBTLRewards, 0); // No rewards initially
        assertGe(pendingUSD1Dividends, 0); // Could be 0 or some amount depending on dividends
    }

    function testOpenTrading() public {
        // Only owner should be able to open trading
        bitluck.openTrading();
        assertTrue(bitluck.startTradeBlock() > 0);
    }

    function testCannotOpenTradingTwice() public {
        bitluck.openTrading();

        vm.expectRevert("Trading has already started");
        bitluck.openTrading();
    }

    function testOnlyOwnerCanOpenTrading() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        bitluck.openTrading();
    }

    function testSetDrawInterval() public {
        bitluck.setDrawInterval(2400); // 1 hour
        assertEq(bitluck.drawIntervalBlocks(), 2400);
    }

    function testCannotSetTooShortDrawInterval() public {
        vm.expectRevert("Interval too short");
        bitluck.setDrawInterval(50);
    }

    function testOnlyOwnerCanSetDrawInterval() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        bitluck.setDrawInterval(2400);
    }

    function testSetBatchSize() public {
        bitluck.setBatchSize(200);
        assertEq(bitluck.batchSize(), 200);
    }

    function testCannotSetInvalidBatchSize() public {
        vm.expectRevert("Invalid batch size");
        bitluck.setBatchSize(0);

        vm.expectRevert("Invalid batch size");
        bitluck.setBatchSize(600);
    }

    function testSetHolderCondition() public {
        uint256 newCondition = 500000000 * 10 ** 9; // 0.05%
        bitluck.setHolderCondition(newCondition);
        assertEq(bitluck.holderCondition(), newCondition);
    }

    function testCannotSetInvalidHolderCondition() public {
        vm.expectRevert("Invalid condition");
        bitluck.setHolderCondition(0);
    }

    function testBlocksUntilNextDraw() public {
        bitluck.openTrading(); // This sets lastDrawBlock

        uint256 blocks = bitluck.blocksUntilNextDraw();
        assertEq(blocks, bitluck.drawIntervalBlocks());

        // Simulate blocks passing
        vm.roll(block.number + bitluck.drawIntervalBlocks());

        blocks = bitluck.blocksUntilNextDraw();
        assertEq(blocks, 0);
    }

    function testReferralSystem() public {
        // Test referral info for new user
        (address userReferrer, uint256 earnings, bool hasDeposited_) = bitluck
            .getReferralInfo(user1);
        assertEq(userReferrer, address(0));
        assertEq(earnings, 0);
        assertFalse(hasDeposited_);

        // Set referrer and stake
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, referrer);

        // Check referral info after staking
        (userReferrer, earnings, hasDeposited_) = bitluck.getReferralInfo(
            user1
        );
        assertEq(userReferrer, referrer);
        assertEq(earnings, 0); // User doesn't earn from referring others
        assertTrue(hasDeposited_);

        // Check referrer earnings
        (, uint256 referrerEarnings, ) = bitluck.getReferralInfo(referrer);
        assertEq(referrerEarnings, (STAKE_AMOUNT * 1000) / 10000);
    }

    function testCannotReferSelf() public {
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, user1); // Try to refer self

        (address userReferrer, , ) = bitluck.getReferralInfo(user1);
        assertEq(userReferrer, address(0)); // Should not set self as referrer
    }

    function testGetUSD1Balance() public view {
        uint256 balance = bitluck.getUSD1Balance();
        assertGe(balance, 0);
    }

    function testFeeConstants() public view {
        assertEq(bitluck._buyUSD1Fee(), 300); // 3%
        assertEq(bitluck._buyMarketingFee(), 100); // 1%
        assertEq(bitluck._sellUSD1Fee(), 300); // 3%
        assertEq(bitluck._sellMarketingFee(), 100); // 1%
    }

    function testRenounceOwnership() public {
        bitluck.renounceOwnership();
        assertEq(bitluck.owner(), address(0));
    }

    function testMultipleUsersStaking() public {
        // User1 stakes with referrer
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, referrer);

        // User2 stakes without referrer
        vm.prank(user2);
        bitluck.stakeBTL(STAKE_AMOUNT * 2, address(0));

        // User3 stakes with user1 as referrer
        vm.prank(user3);
        bitluck.stakeBTL(STAKE_AMOUNT / 2, user1);

        // Check total staked
        uint256 expectedTotal = ((STAKE_AMOUNT * 90) / 100) +
            (STAKE_AMOUNT * 2) +
            (((STAKE_AMOUNT / 2) * 90) / 100);
        assertEq(bitluck.totalStakedBTL(), expectedTotal);

        // Check individual stakes
        assertEq(bitluck.stakedBTL(user1), (STAKE_AMOUNT * 90) / 100);
        assertEq(bitluck.stakedBTL(user2), STAKE_AMOUNT * 2);
        assertEq(bitluck.stakedBTL(user3), ((STAKE_AMOUNT / 2) * 90) / 100);
    }

    // Test edge cases
    function testStakeMinimumAmount() public {
        vm.prank(user1);
        bitluck.stakeBTL(1, address(0));

        assertEq(bitluck.stakedBTL(user1), 1);
    }

    function testUnstakeAll() public {
        vm.prank(user1);
        bitluck.stakeBTL(STAKE_AMOUNT, address(0));

        vm.prank(user1);
        bitluck.unstakeBTL(STAKE_AMOUNT);

        assertEq(bitluck.stakedBTL(user1), 0);
        assertEq(bitluck.totalStakedBTL(), 0);
    }

    function testReceiveAndFallback() public {
        // Test receive function
        (bool success, ) = payable(address(bitluck)).call{value: 1 ether}("");
        assertTrue(success);

        // Test fallback function
        (success, ) = payable(address(bitluck)).call{value: 1 ether}("0x1234");
        assertTrue(success);

        assertEq(address(bitluck).balance, 2 ether);
    }

    function testConstructorValidation() public {
        // Test invalid USDT address
        vm.expectRevert("Invalid USD1 address");
        new BitLuck(address(0), address(router));

        // Test invalid router address
        vm.expectRevert("Invalid router address");
        new BitLuck(address(usdt), address(0));
    }
}
