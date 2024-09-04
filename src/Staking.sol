// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console2} from "forge-std/console2.sol";

contract StakingManager is Ownable {
    using SafeERC20 for IERC20;

    error Staking_ZeroAmt();
    error Staking_ZeroAddr();

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event PoolInitialized(address indexed stakingToken, address indexed rewardToken, uint256 duration, uint256 rewards);

    /*//////////////////////////////////////////////////////////////
                               STATE VARS
    //////////////////////////////////////////////////////////////*/
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    IERC20 public s_stakingToken;
    IERC20 public s_rewardToken;
    //timestamp for finishing the staking round
    uint256 public s_finishAt;
    //time duration for staking round
    uint256 public s_duration;
    uint256 public s_totalSupply;
    //reward accumulator index
    uint256 public s_rewardAcc;
    // updates everyime a new staker stakes or withdraws
    uint256 private s_rewardPerTokenPerBlock;
    //block number for when the pool was last updated
    uint256 private s_lastBlockUpdated;
    uint256 private i_secondsPerBlock;
    mapping(address => UserInfo) public s_userInfo;
    //rewards per block
    uint256 private s_rewardRate;

    // precision factor for rewardAcc
    uint64 constant PRECISION = 1e12;

    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        s_stakingToken = IERC20(_stakingToken);
        s_rewardToken = IERC20(_rewardToken);
    }

    // external func

    /// @notice sets the pool's config
    /// @dev sets rewardRate as rewards per sec
    /// @param _rewards the TOTAL amount of rewards to be distributed
    function setPool(address _depositor, uint256 _duration, uint256 _rewards, uint256 _secondsPerBlock)
        external
        onlyOwner
    {
        s_duration = _duration;
        uint256 blockCount = _duration / _secondsPerBlock;
        s_rewardRate = _rewards / blockCount;
        s_finishAt = block.timestamp + _duration;
        s_rewardAcc = 0;
        s_rewardPerTokenPerBlock = 0;

        s_rewardToken.safeTransferFrom(_depositor, address(this), _rewards);
    }

    function stakeTokens(uint256 _amt) external {
        if (_amt <= 0) {
            revert Staking_ZeroAmt();
        }
        updatePool();
        UserInfo storage user = s_userInfo[msg.sender];
        user.amount += _amt;
        user.rewardDebt += (_amt * s_rewardAcc) / 1e18;

        s_stakingToken.safeTransferFrom(msg.sender, address(this), _amt);
    }

    function withdrawTokens(uint256 _amt) external {
        if (_amt <= 0) {
            revert Staking_ZeroAmt();
        }
        updatePool();
        UserInfo storage user = s_userInfo[msg.sender];
        console2.log("user.amount", user.amount);
        user.amount -= _amt;
        user.rewardDebt = (user.amount * s_rewardAcc) / 1e18;

        s_stakingToken.safeTransfer(msg.sender, _amt);
    }

    function claimReward() external {
        updatePool();
        UserInfo storage user = s_userInfo[msg.sender];
        console2.log("rewardAcc", s_rewardAcc);
        console2.log("user.amount", user.amount);
        console2.log("user debt", user.rewardDebt);
        uint256 reward = (user.amount * s_rewardAcc) / 1e18 - user.rewardDebt;
        user.rewardDebt = user.amount;
        s_rewardToken.safeTransfer(msg.sender, reward);
    }

    //internal function
    function updatePool() internal {
        uint256 _lastUpdatedBlock = s_lastBlockUpdated;
        if (block.number <= _lastUpdatedBlock) {
            return;
        }
        uint256 blockInterval = block.number - _lastUpdatedBlock;
        s_totalSupply = s_stakingToken.balanceOf(address(this));
        console2.log("s_totalSupply", s_totalSupply);
        if (s_totalSupply == 0) {
            s_lastBlockUpdated = block.number;
            return;
        }
        s_rewardPerTokenPerBlock = (s_rewardRate * 1e18) / s_totalSupply;
        console2.log("rewardRate", s_rewardRate);
        console2.log("s_rewardPerTokenPerBlock", s_rewardPerTokenPerBlock);
        console2.log("block interval", blockInterval);
        console2.log("reward issued", s_rewardAcc + s_rewardPerTokenPerBlock * blockInterval);
        console2.log("reward Acc", s_rewardAcc);
        s_rewardAcc += s_rewardPerTokenPerBlock * blockInterval;
        s_lastBlockUpdated = block.number;
    }

    //View

    /// @param _user adddress of the user
    /// @return rewards hitherto earned by the user on thier staked tokens
    function earned(address _user) external view returns (uint256) {
        if (_user == address(0)) {
            revert Staking_ZeroAddr();
        }
        UserInfo storage user = s_userInfo[_user];
        return user.amount * s_rewardAcc - user.rewardDebt;
    }

    // Getters

    function getRewardRate() external view returns (uint256) {
        return s_rewardRate;
    }

    function getUserInfo(address _user) external view returns (uint256, uint256) {
        UserInfo storage user = s_userInfo[_user];
        return (user.amount, user.rewardDebt);
    }
}
