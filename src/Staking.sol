// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract Staking is Ownable {
    using SafeERC20 for IERC20;

    error Staking_ZeroAmt();
    error Staking_ZeroAddr();

    /*//////////////////////////////////////////////////////////////
                               STATE VARS
    //////////////////////////////////////////////////////////////*/
    struct UserInfo{
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
    uint256 public s_rewardPerTokenPerBlock;
    //block number for when the pool was last updated
    uint256 public lastBlockUpdated;
    mapping(address => UserInfo) public s_userInfo;
    uint256 public s_rewardRate;

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
    function setPool(uint256 _duration, uint256 _rewards) external onlyOwner {
        s_duration = _duration;
        s_rewardRate = _rewards / _duration;
        s_finishAt = block.timestamp + _duration;
        s_rewardAcc = 0;
        s_rewardPerTokenPerBlock = 0;

        // transfer rewards to the contract ?
    }

    function stakeTokens(uint256 _amt) external {
        if (_amt <= 0) {
            revert Staking_ZeroAmt();
        }
        updatePool();
        UserInfo storage user = s_userInfo[msg.sender];   
        user.amount += _amt;
        user.rewardDebt += _amt * s_rewardAcc;

        IERC20(s_stakingToken).safeTransferFrom(msg.sender, address(this), _amt);
    }

    function withdrawTokens(uint256 _amt) external {

    }

    function claimReward() external {

    }

    //internal function
    function updatePool() internal {
        uint256 _lastUpdatedBlock = lastBlockUpdated;
        uint256 blockInterval = block.number - _lastUpdatedBlock;
        uint256 rewardIssued = s_rewardPerTokenPerBlock * blockInterval;
        s_rewardAcc += rewardIssued;
        s_lastBlockUpdated = block.number;
    }

    //View 

    /// @param _user adddress of the user
    /// @return rewards hitherto earned by the user on thier staked tokens
    function earned(address _user) external view returns(uint256) {
        if (_user == address(0)) {
            revert Staking_ZeroAddr();
        }
        UserInfo storage user = s_userInfo[_user];
    }
}
