// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {StakingManager} from "src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract StakingManagerTest is Test {
    StakingManager stakingManager;
    ERC20Mock stakingToken;
    ERC20Mock rewardToken;
    address owner = address(this);
    address user1 = address(0x1);
    address user2 = address(0x2);
    address user3 = address(0x3);

    uint256 initialSupply = 1e24;
    uint256 rewardAmount = 1e20;
    uint256 stakingDuration = 86400; // 1 hour
    uint256 secondsPerBlock = 12;
    //1000000000000000000
    //333333333333333333
    //333333333333333333
    //11111111111111111100

    function setUp() public {
        stakingToken = new ERC20Mock("StakingToken", "STK", address(this), initialSupply);
        rewardToken = new ERC20Mock("RewardToken", "RWD", address(this), initialSupply);

        stakingManager = new StakingManager(address(stakingToken), address(rewardToken));

        // Transfer reward tokens to contract for rewards distribution
        rewardToken.mint(owner, rewardAmount);
        rewardToken.approve(address(stakingManager), rewardAmount);

        // Set up the staking pool
        stakingManager.setPool(owner, stakingDuration, rewardAmount, secondsPerBlock);
    }

    function testStakeTokens() public {
        uint256 stakeAmount = 1e18;

        stakingToken.mint(user1, stakeAmount);
        vm.prank(user1);
        stakingToken.approve(address(stakingManager), stakeAmount);

        // User1 stakes tokens
        vm.prank(user1);
        stakingManager.stakeTokens(stakeAmount);

        // Check the user's staked amount
        (uint256 amount,) = stakingManager.s_userInfo(user1);
        assertEq(amount, stakeAmount);
    }

    function testClaimReward() public {
        uint256 stakeAmount = 1e18;

        stakingToken.mint(user1, stakeAmount);
        vm.prank(user1);
        stakingToken.approve(address(stakingManager), stakeAmount);

        // User1 stakes tokens
        vm.prank(user1);
        stakingManager.stakeTokens(stakeAmount);

        // Advance time to accumulate rewards
        vm.roll(block.number + 100);

        // User1 claims reward
        vm.prank(user1);
        stakingManager.claimReward();

        // Check the user's reward balance
        uint256 rewardBalance = rewardToken.balanceOf(user1);
        assertTrue(rewardBalance > 0);
    }

    function testWithdrawTokens() public {
        uint256 stakeAmount = 1e18;

        stakingToken.mint(user1, stakeAmount);
        vm.prank(user1);
        stakingToken.approve(address(stakingManager), stakeAmount);

        // User1 stakes tokens
        vm.prank(user1);
        stakingManager.stakeTokens(stakeAmount);

        // Advance time to accumulate rewards
        vm.roll(block.number + 100);

        // User1 withdraws tokens
        vm.prank(user1);
        stakingManager.withdrawTokens(stakeAmount);

        // Check if tokens have been withdrawn
        uint256 userBalance = stakingToken.balanceOf(user1);
        assertEq(userBalance, stakeAmount);
    }

    function testIntegration() public {
        //reward Rate
        uint256 rR = stakingManager.getRewardRate();

        uint256 stakeAmount2 = 2e18;

        stakingToken.mint(user2, stakeAmount2);

        // User2 stakes tokens
        vm.prank(user2);
        stakingToken.approve(address(stakingManager), stakeAmount2);
        vm.prank(user2);
        stakingManager.stakeTokens(stakeAmount2);

        // Advance time and blocks
        vm.roll(block.number + 100);

        // User2 withdraws tokens and claims reward
        vm.startPrank(user2);
        (uint256 amt, uint256 debt) = stakingManager.getUserInfo(user2);
        stakingManager.claimReward();
        // Check User2's reward balance and staked tokens
        uint256 rewardBalanceUser2 = rewardToken.balanceOf(user2);
        uint256 rewardExpectedParam = (rR * 100 * 1e18) / stakingManager.s_totalSupply();
        emit log_uint(rR);
        emit log_uint(amt);
        uint256 rewardExpected = ((amt * rewardExpectedParam) / 1e18) - debt;
        emit log_uint(rewardExpected);
        emit log_uint(rewardBalanceUser2);
        assertTrue(rewardBalanceUser2 == rewardExpected);

        stakingManager.withdrawTokens(stakeAmount2);
        assertEq(stakingToken.balanceOf(user2), stakeAmount2);
    }

    function testIntegrationWithMultipleUsers() public {
        // Initial reward rate
        uint256 rR = stakingManager.getRewardRate();
        console2.log("reward rate", rR);

        // Stake amounts for different users
        uint256 stakeAmount1 = 1e18;
        uint256 stakeAmount2 = 2e18;
        uint256 stakeAmount3 = 3e18;

        // Mint tokens for users
        stakingToken.mint(user1, stakeAmount1);
        stakingToken.mint(user2, stakeAmount2);
        stakingToken.mint(user3, stakeAmount3);

        // User1 stakes tokens
        vm.prank(user1);
        stakingToken.approve(address(stakingManager), stakeAmount1);
        vm.prank(user1);
        stakingManager.stakeTokens(stakeAmount1);

        // Advance time and blocks
        vm.roll(block.number + 50);

        // User2 stakes tokens
        vm.prank(user2);
        stakingToken.approve(address(stakingManager), stakeAmount2);
        vm.prank(user2);
        stakingManager.stakeTokens(stakeAmount2);

        // Advance time and blocks
        vm.roll(block.number + 75);

        // User3 stakes tokens
        vm.prank(user3);
        stakingToken.approve(address(stakingManager), stakeAmount3);
        vm.prank(user3);
        stakingManager.stakeTokens(stakeAmount3);

        // Advance time and blocks
        vm.roll(block.number + 100);

        // User1 withdraws tokens and claims reward
        vm.startPrank(user1);
        (uint256 amt1, uint256 debt1) = stakingManager.getUserInfo(user1);
        stakingManager.claimReward();
        uint256 rewardBalanceUser1 = rewardToken.balanceOf(user1);
        uint256 rewardExpected1 = ((amt1 * stakingManager.s_rewardAcc()) / 1e18) - debt1;
        console2.log("reward amt for user1", rewardExpected1);
        assertTrue(rewardBalanceUser1 == rewardExpected1);
        stakingManager.withdrawTokens(stakeAmount1);
        assertEq(stakingToken.balanceOf(user1), stakeAmount1);

        // User2 withdraws tokens and claims reward
        vm.startPrank(user2);
        (uint256 amt2, uint256 debt2) = stakingManager.getUserInfo(user2);
        stakingManager.claimReward();
        uint256 rewardBalanceUser2 = rewardToken.balanceOf(user2);
        uint256 rewardExpected2 = ((amt2 * stakingManager.s_rewardAcc()) / 1e18) - debt2;
        console2.log("reward amt for user2", rewardExpected2);
        assertTrue(rewardBalanceUser2 == rewardExpected2);
        stakingManager.withdrawTokens(stakeAmount2);
        assertEq(stakingToken.balanceOf(user2), stakeAmount2);

        // User3 withdraws tokens and claims reward
        vm.startPrank(user3);
        (uint256 amt3, uint256 debt3) = stakingManager.getUserInfo(user3);
        stakingManager.claimReward();
        uint256 rewardBalanceUser3 = rewardToken.balanceOf(user3);
        uint256 rewardExpected3 = ((amt3 * stakingManager.s_rewardAcc()) / 1e18) - debt3;
        console2.log("reward amt for user3", rewardExpected3);
        assertTrue(rewardBalanceUser3 == rewardExpected3);
        stakingManager.withdrawTokens(stakeAmount3);
        assertEq(stakingToken.balanceOf(user3), stakeAmount3);

        /**
         * results are:
         * reward rate is 0.0138 eth
         * u1: 225 blocks 1.27 eth reward (actual ans is 1.258)
         * u2: 175 blocks 1.157 eth reward (actual ans is 1.136)
         * u3: 75 blocks 0.694 reward (actual is 0.669)
         * 96-98% accurate
         */
    }

    function testIntegrationWithMultipleUsersAdditionalStake() public {
        // Initial reward rate
        uint256 rR = stakingManager.getRewardRate();
        console2.log("reward rate", rR);

        // Stake amounts for different users
        uint256 stakeAmount1 = 1e18;
        uint256 stakeAmount2 = 2e18;
        uint256 stakeAmount3 = 3e18;
        uint256 additionalStakeUser1 = 4e18; // Additional stake for user1

        // Mint tokens for users
        stakingToken.mint(user1, stakeAmount1 + additionalStakeUser1); // Mint total amount for user1
        stakingToken.mint(user2, stakeAmount2);
        stakingToken.mint(user3, stakeAmount3);

        // User1 stakes initial tokens
        vm.prank(user1);
        stakingToken.approve(address(stakingManager), stakeAmount1);
        vm.prank(user1);
        stakingManager.stakeTokens(stakeAmount1);

        // Advance time and blocks
        vm.roll(block.number + 50);

        // User2 stakes tokens
        vm.prank(user2);
        stakingToken.approve(address(stakingManager), stakeAmount2);
        vm.prank(user2);
        stakingManager.stakeTokens(stakeAmount2);

        // Advance time and blocks
        vm.roll(block.number + 75);

        // User1 stakes additional tokens at the same time as User3 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(stakingManager), additionalStakeUser1);
        stakingManager.stakeTokens(additionalStakeUser1);
        vm.stopPrank();

        vm.prank(user3);
        stakingToken.approve(address(stakingManager), stakeAmount3);
        vm.prank(user3);
        stakingManager.stakeTokens(stakeAmount3);

        // Advance time and blocks
        vm.roll(block.number + 100);

        // User1 withdraws tokens and claims reward
        vm.startPrank(user1);
        (uint256 amt1, uint256 debt1) = stakingManager.getUserInfo(user1);
        stakingManager.claimReward();
        uint256 rewardBalanceUser1 = rewardToken.balanceOf(user1);
        uint256 rewardExpected1 = ((amt1 * stakingManager.s_rewardAcc()) / 1e18) - debt1;
        console2.log("reward amt for user1", rewardExpected1);
        assertTrue(rewardBalanceUser1 == rewardExpected1);
        stakingManager.withdrawTokens(stakeAmount1 + additionalStakeUser1);
        assertEq(stakingToken.balanceOf(user1), stakeAmount1 + additionalStakeUser1);

        // User2 withdraws tokens and claims reward
        vm.startPrank(user2);
        (uint256 amt2, uint256 debt2) = stakingManager.getUserInfo(user2);
        stakingManager.claimReward();
        uint256 rewardBalanceUser2 = rewardToken.balanceOf(user2);
        uint256 rewardExpected2 = ((amt2 * stakingManager.s_rewardAcc()) / 1e18) - debt2;
        console2.log("reward amt for user2", rewardExpected2);
        assertTrue(rewardBalanceUser2 == rewardExpected2);
        stakingManager.withdrawTokens(stakeAmount2);
        assertEq(stakingToken.balanceOf(user2), stakeAmount2);

        // User3 withdraws tokens and claims reward
        vm.startPrank(user3);
        (uint256 amt3, uint256 debt3) = stakingManager.getUserInfo(user3);
        stakingManager.claimReward();
        uint256 rewardBalanceUser3 = rewardToken.balanceOf(user3);
        uint256 rewardExpected3 = ((amt3 * stakingManager.s_rewardAcc()) / 1e18) - debt3;
        console2.log("reward amt for user3", rewardExpected3);
        assertTrue(rewardBalanceUser3 == rewardExpected3);
        stakingManager.withdrawTokens(stakeAmount3);
        assertEq(stakingToken.balanceOf(user3), stakeAmount3);

        /**
         * The test results might look something like this:
         * reward rate: 0.0138 ETH per block
         * User1 (with additional stake): reward = X ETH (expected to be higher due to additional stake)
         * User2: reward = Y ETH
         * User3: reward = Z ETH (accounting for the fact that user1 added more to the pool)
         */
    }
}
