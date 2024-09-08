// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "./interfaces/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouter} from "./interfaces/IRouter.sol";

contract NFTStakingManager is Ownable {
    error SM_InvalidQuantity();
    error SM_NotEnoughNFTBalance();
    error SM_BadgeForLvlMissing();

    event NFTStaked(address indexed user, uint256 quantity);
    event NFTUnstaked(address indexed user, uint256 quantity);

    struct User {
        uint256 stakedNFTs;
        uint256 stakedRewardTokens;
        uint256 lockingPeriod;
        uint256 pendingRewards;
        uint256 lastRewarded;
        bool isBoosted;
        // similar to bitMaps really [1 2 3 4 5] where if badge of lvl 3 has been acquired then badge[3-1] == 3 (true)
        uint8[5] badges;
        // 2^8 = 256 levels possible
        uint8 currentLevel;
    }

    // On BNB smart chain
    address private constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // address of Uniswap Router
    address private constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // address of USDC token
    uint256 private constant LOCKING_PERIOD = 6 weeks;
    uint256 private constant SECS_IN_YEAR = 31536000;

    IERC721 private immutable s_nftToken;
    IERC20 private immutable s_rewardToken;
    IRouter private immutable s_router = IRouter(ROUTER);

    mapping(address => User) public s_users;
    uint256[5] private s_APRs;
    uint256[5] private s_boostedAPRs;
    // min tokens the user must have in order to lock their tokens for staking (q why the exclusivity here?)
    uint256[5] private s_boosterRewards;
    uint256[5] private s_badgeCosts;
    // min about of tokens required to be had for getting each badge
    uint256[5] private s_badgePreReqs;
    // max 5 valid currencies,to buy the badges from
    address[5] private s_validCurrencies;
    // Mapping from user address to an array of staked NFT IDs.
    mapping(address user => uint256[]) private s_stakedIds;

    constructor() Ownable(msg.sender) {}

    // Externals

    function stakeNFT(uint256 _quantity) external {
        // quant of NFTs to stake (ensure > 0) + owned by the owner
        // ensure that the user has sufficient badges to stake the tokens
        // add the rewards earned hither to the user's pending rewards to offset the effect of resetting the lastRewardTime

        //@explain this is to offset the effect of reinit the lastRewardTime for user
        // if user makes multiple stakes, and each time we reset the lastRewardTime to current ts; then
        // at the end during rewardClaim the timePeriod for staking would be current TS - lastRewardTs (when latest stake was made)
        // thereby nullifying the rewards accumulated on prev staked amts

        // transfer NFTs to the contract
        // update user's state (update level, badges, )
        if (_quantity == 0) {
            revert SM_InvalidQuantity();
        }
        uint256[] memory tokenIds = s_nftToken.walletOfOwner(msg.sender);
        if (tokenIds.length < _quantity) {
            revert SM_NotEnoughNFTBalance();
        }

        uint8 expectedLvl = _getLevel(_quantity);
        (, bool ok) = _getBadge(msg.sender, expectedLvl);
        if (!ok) {
            revert SM_BadgeForLvlMissing();
        }

        User memory user = s_users[msg.sender];

        if (user.stakedNFTs > 0) {
            uint256 rewards = earned(msg.sender);
            user.pendingRewards += rewards;
        }

        for (uint256 i = 0; i < _quantity; ++i) {
            s_nftToken.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
            s_stakedIds[msg.sender].push(tokenIds[i]);
        }

        user.stakedNFTs += _quantity;
        _updateLevel(msg.sender);
        s_users[msg.sender] = user;

        emit NFTStaked(msg.sender, _quantity);
    }

    function unstakeNFT(uint256 _quantity) external {
        if (_quantity == 0) {
            revert SM_InvalidQuantity();
        }
        User memory user = s_users[msg.sender];
        if (user.stakedNFTs < _quantity) {
            revert SM_NotEnoughNFTBalance();
        }

        if (user.stakedNFTs > 0) {
            uint256 rewards = earned(msg.sender);
            user.pendingRewards += rewards;
        }

        uint256[] storage tokenIds = s_stakedIds[msg.sender];

        for (uint256 i = 0; i < _quantity; ++i) {
            s_nftToken.safeTransferFrom(address(this), msg.sender, tokenIds[tokenIds.length - 1]);
            tokenIds.pop();
        }

        user.stakedNFTs -= _quantity;
        if (user.stakedNFTs == 0) {
            user.lastRewarded = 0;
        } else {
            user.lastRewarded = block.timestamp;
        }

        _updateLevel(msg.sender);
        s_users[msg.sender] = user;

        emit NFTUnstaked(msg.sender, _quantity);
    }

    function stakeTokens(uint256[] memory _nftIds) external {
        // Staking logic
    }

    function unstakeTokens(uint256[] memory _nftIds) external {
        // Staking logic
    }

    // Internals

    function _getLevel(uint256 _nfts) internal view returns (uint8) {
        // if nfts are 3 and first lvl's pre Req is max 1-5 ; then 3 < 5 and hence lvl 1
        if (_nfts == 0) return 0;
        else if (_nfts <= s_badgePreReqs[0]) return 1;
        else if (_nfts <= s_badgePreReqs[1]) return 2;
        else if (_nfts <= s_badgePreReqs[2]) return 3;
        else if (_nfts <= s_badgePreReqs[3]) return 4;
        else return 5;
    }

    // returns estimated badge levels given a sender's address and their current level
    function _getBadge(address _sender, uint8 _level) internal view returns (uint8 badge, bool hasBadgeForLevel) {
        // [1 2 3 4 5] => badge levels
        if (_level == 0) return (0, false);
        User memory user = s_users[_sender];
        if (user.badges[_level - 1] != 0) {
            return (badge = user.badges[_level - 1], true);
        } else {
            // if the user doesn't have the badge at the `_level` then check for the prev levels
            for (uint256 i = (_level - 1); i > 0; --i) {
                if (i == user.badges[i - 1]) {
                    return (badge = user.badges[i - 1], false);
                }
            }
        }
    }

    function _updateLevel(address _sender) internal {
        // update the user's level based on the number of NFTs staked
        User memory user = s_users[_sender];
        uint8 expectedLvl = _getLevel(user.stakedNFTs);
        // if the exepctedLvl is not equal to the current level; then the new level shoudl be depdendent on the badge that user owns
        // if expectedBadge == expectedLevel that that means user has the badge for the expected level
        // if not, the newLvl should be equal to the current badge that teh user owns; this shall incentivize them to
        // buy the badge for the expected level
        if (expectedLvl != 0) {
            uint8 currentLvl = user.currentLevel;
            if (expectedLvl != currentLvl) {
                // hasBadge shows user has the badge for the expected level
                (uint8 expectedBadge, bool hasBadge) = _getBadge(_sender, expectedLvl);
                if (hasBadge) {
                    user.currentLevel = expectedLvl;
                } else {
                    user.currentLevel = expectedBadge;
                }

                //updating user's booster status etc
                if (s_boosterRewards[user.currentLevel - 1] > user.stakedRewardTokens) {
                    user.isBoosted = false;
                } else {
                    user.isBoosted = true;
                    //q why increase the locking period here?
                    //since the user's level has been upgraded their staked tokens (if any) need to be locked
                    //for an additonal time in order for the user to enjoy the APR for the new level
                    user.lockingPeriod = block.timestamp + LOCKING_PERIOD;
                }
                s_users[_sender] = user;
            }
        } else {
            user.currentLevel = 0;
            user.isBoosted = false;
            s_users[_sender] = user;
        }
    }

    function earned(address _user) public view returns (uint256 rewards) {
        // returns the rewards earned by the user
        //rewards earned = tokens staked * time staked * APR/sec
        User memory user = s_users[_user];

        if (user.stakedNFTs > 0) {
            uint256 timeStaked = block.timestamp - user.lastRewarded;
            uint256 APR = user.isBoosted ? s_boostedAPRs[user.currentLevel - 1] : s_APRs[user.currentLevel - 1];
            uint256 aprSec = APR / SECS_IN_YEAR;
            rewards = user.stakedNFTs * timeStaked * aprSec;
        }
    }
}
