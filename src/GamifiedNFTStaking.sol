// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "./interfaces/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NFTStakingManager is Ownable {
    struct User {
        uint256 stakedNFTs;
        uint256 stakedRewardTokens;
        uint256 lockingPeriod;
        uint256 pendingRewards;
        uint256 lastRewarded;
        bool isBoosted;
        uint256[5] badges;
        // 2^8 = 256 levels possible
        uint8 currentLevel;
    }

    IERC721 public immutable s_nftToken;
    IERC20 public immutable s_rewardToken;

    mapping(address => User) public s_users;
    uint256[5] private s_APRs;
    uint256[5] private s_boostedAPRs;
    // min tokens the user must have in order to lock their tokens for staking (q why the exclusivity here?)
    uint256[5] private s_boosterRewards;
    uint256[5] private s_badgeCosts;
    // max 5 valid currencies,to buy the badges from
    address[5] private s_validCurrencies;

    constructor() Ownable(msg.sender) {}

    // Externals

    function stakeNFT(uint256[] memory _nftIds) external {
        // Staking logic
    }

    function unstakeNFT(uint256[] memory _nftIds) external {
        // Staking logic
    }

    function stakeTokens(uint256[] memory _nftIds) external {
        // Staking logic
    }

    function unstakeTokens(uint256[] memory _nftIds) external {
        // Staking logic
    }
}
