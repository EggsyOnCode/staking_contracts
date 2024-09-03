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

    uint256 initialSupply = 1e24;
    uint256 rewardAmount = 1e20;
    uint256 stakingDuration = 3600; // 1 hour
    uint256 secondsPerBlock = 12;

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
        uint256 stakeAmount1 = 1e18;
        uint256 stakeAmount2 = 2e18;

        stakingToken.mint(user1, stakeAmount1);
        stakingToken.mint(user2, stakeAmount2);

        // User1 stakes tokens
        vm.prank(user1);
        stakingToken.approve(address(stakingManager), stakeAmount1);
        vm.prank(user1);
        stakingManager.stakeTokens(stakeAmount1);

        // User2 stakes tokens
        vm.prank(user2);
        stakingToken.approve(address(stakingManager), stakeAmount2);
        vm.prank(user2);
        stakingManager.stakeTokens(stakeAmount2);

        // Advance time and blocks
        vm.roll(block.number + 100);

        // // User1 claims reward
        // vm.prank(user1);
        // stakingManager.claimReward();

        // // Check User1's reward balance
        // uint256 rewardBalanceUser1 = rewardToken.balanceOf(user1);
        // assertTrue(rewardBalanceUser1 > 0);

        // User2 withdraws tokens and claims reward
        vm.startPrank(user2);
        stakingManager.withdrawTokens(stakeAmount2);
        stakingManager.claimReward();

        // Check User2's reward balance and staked tokens
        uint256 rewardBalanceUser2 = rewardToken.balanceOf(user2);
        assertTrue(rewardBalanceUser2 > 0);
        assertEq(stakingToken.balanceOf(user2), stakeAmount2);
    }
}
