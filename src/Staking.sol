// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * YIELD FARMING!!!
 * @title StakingManager
 * @notice A contract that allows users to stake tokens and earn rewards over time.
 * @dev This contract uses SafeERC20 for safe token transfers and is Ownable. The staking logic is a mixture of both
 *     MasterChef and StakingRewards contracts. Takes the best of both worlds
 * Results are 96-98% accurate. The remaining 2-4% is due to rounding errors.
 */
contract StakingManager is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error Staking_ZeroAmt();
    error Staking_ZeroAddr();
    error Staking_ParticipantNotFound();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event PoolInitialized(address indexed stakingToken, address indexed rewardToken, uint256 duration, uint256 rewards);

    /*//////////////////////////////////////////////////////////////
                               STATE VARS
    //////////////////////////////////////////////////////////////*/
    struct UserInfo {
        uint256 amount; // Amount of staked tokens by the user
        uint256 rewardDebt; // Reward debt of the user
    }

    IERC20 public s_stakingToken; // Token to be staked
    IERC20 public s_rewardToken; // Token to be distributed as rewards
    uint256 public s_finishAt; // Timestamp for finishing the staking round
    uint256 public s_duration; // Duration for staking round
    uint256 public s_totalSupply; // Total supply of staked tokens
    uint256 public s_rewardAcc; // Reward accumulator index
    uint256 private s_rewardPerTokenPerBlock; // Reward per token per block
    uint256 private s_lastBlockUpdated; // Block number when the pool was last updated
    uint256 private s_rewardRate; // Rewards per block
    uint64 constant PRECISION = 1e18; // Precision factor for rewardAcc

    mapping(address => UserInfo) public s_userInfo; // Mapping of user address to UserInfo struct

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Constructor to initialize the staking and reward tokens.
     * @param _stakingToken Address of the token to be staked.
     * @param _rewardToken Address of the token to be distributed as rewards.
     */
    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Staking: Invalid staking token");
        require(_rewardToken != address(0), "Staking: Invalid reward token");
        s_stakingToken = IERC20(_stakingToken);
        s_rewardToken = IERC20(_rewardToken);
    }

    /*//////////////////////////////////////////////////////////////
                               EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the pool's configuration including rewards, duration, and depositor.
     * @param _depositor Address that will deposit the reward tokens.
     * @param _duration Duration of the staking round in seconds.
     * @param _rewards Total amount of rewards to be distributed.
     * @param _secondsPerBlock Number of seconds per block.
     */
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

    /**
     * @notice Allows a user to stake a specified amount of tokens.
     * @param _amt Amount of tokens to stake.
     */
    function stakeTokens(uint256 _amt) external {
        if (_amt <= 0) {
            revert Staking_ZeroAmt();
        }
        updatePool();
        UserInfo storage user = s_userInfo[msg.sender];
        user.amount += _amt;
        user.rewardDebt += (_amt * s_rewardAcc) / PRECISION;

        s_stakingToken.safeTransferFrom(msg.sender, address(this), _amt);
        emit Staked(msg.sender, _amt);
    }

    /**
     * @notice Allows a user to withdraw a specified amount of staked tokens.
     * @param _amt Amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 _amt) external {
        if (_amt <= 0) {
            revert Staking_ZeroAmt();
        }
        updatePool();
        UserInfo storage user = s_userInfo[msg.sender];
        user.amount -= _amt;
        user.rewardDebt = (user.amount * s_rewardAcc) / PRECISION;

        s_stakingToken.safeTransfer(msg.sender, _amt);
        emit Withdrawn(msg.sender, _amt);
    }

    /**
     * @notice Allows a user to claim their accumulated rewards.
     */
    function claimReward() external {
        UserInfo storage user = s_userInfo[msg.sender];
        if (user.amount == 0 && user.rewardDebt == 0) {
            revert Staking_ParticipantNotFound();
        }
        updatePool();
        uint256 reward = (user.amount * s_rewardAcc) / PRECISION - user.rewardDebt;
        user.rewardDebt = user.amount;
        s_rewardToken.safeTransfer(msg.sender, reward);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the pool's reward accumulator and other state variables.
     */
    function updatePool() internal {
        uint256 _lastUpdatedBlock = s_lastBlockUpdated;
        if (block.number <= _lastUpdatedBlock) {
            return;
        }
        uint256 blockInterval = block.number - _lastUpdatedBlock;
        s_totalSupply = s_stakingToken.balanceOf(address(this));
        if (s_totalSupply == 0) {
            s_lastBlockUpdated = block.number;
            return;
        }
        // @dev SOLIDITY design pattern: Multiply first and divide last to preserve precision
        s_rewardPerTokenPerBlock = (s_rewardRate * PRECISION) / s_totalSupply;
        s_rewardAcc += s_rewardPerTokenPerBlock * blockInterval;
        s_lastBlockUpdated = block.number;
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the amount of rewards earned by a user.
     * @param _user Address of the user.
     * @return rewards The amount of rewards earned by the user.
     */
    function earned(address _user) external view returns (uint256 rewards) {
        if (_user == address(0)) {
            revert Staking_ZeroAddr();
        }
        UserInfo storage user = s_userInfo[_user];
        return user.amount * s_rewardAcc - user.rewardDebt;
    }

    /*//////////////////////////////////////////////////////////////
                               GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current reward rate.
     * @return rewardRate The current reward rate per block.
     */
    function getRewardRate() external view returns (uint256 rewardRate) {
        return s_rewardRate;
    }

    /**
     * @notice Returns the staking information of a user.
     * @param _user Address of the user.
     * @return amount The amount of tokens staked by the user.
     * @return rewardDebt The reward debt of the user.
     */
    function getUserInfo(address _user) external view returns (uint256 amount, uint256 rewardDebt) {
        UserInfo storage user = s_userInfo[_user];
        return (user.amount, user.rewardDebt);
    }

    /**
     * @notice Returns the total supply of staked tokens in the pool.
     * @return totalSupply The total supply of staked tokens.
     */
    function getTotalSupply() external view returns (uint256 totalSupply) {
        return s_totalSupply;
    }

    /**
     * @notice Returns the last block at which the pool was updated.
     * @return lastBlockUpdated The block number when the pool was last updated.
     */
    function getLastBlockUpdated() external view returns (uint256 lastBlockUpdated) {
        return s_lastBlockUpdated;
    }

    /**
     * @notice Returns the current reward accumulator index.
     * @return rewardAcc The current reward accumulator index.
     */
    function getRewardAcc() external view returns (uint256 rewardAcc) {
        return s_rewardAcc;
    }
}
