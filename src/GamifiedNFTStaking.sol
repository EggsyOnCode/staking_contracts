// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "./interfaces/IERC721.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// 721Receiver cuz staked NFTs are transferred to the contract (for now) we can use a vault later on!
contract NFTStakingManager is Ownable, IERC721Receiver {
    error SM_InvalidQuantity();
    error SM_NotEnoughNFTBalance();
    error SM_NotEnoughProtocolTokens();
    error SM_BadgeForLvlMissing();
    error SM_BadgeAlreadyExists();
    error SM_InvalidCurrency();
    error SM_UserAlreadyBoosted();
    error SM_NotEnoughBalanceForBadgePurchase();
    error SM_LockingPeriodNotOver();
    error SM_NotEligibleForRewards();
    error SM_NoRewardsAvailable();

    event NFTStaked(address indexed user, uint256 indexed quantity);
    event NFTUnstaked(address indexed user, uint256 indexed quantity);
    event BadgeBought(address indexed user, uint8 indexed level);
    event TokensStaked(address indexed user, uint256 indexed quantity);
    event BoostedLvl(address indexed user, uint8 indexed level);
    event TokensUnstaked(address indexed user, uint256 indexed quantity);
    event RewardsDisbursed(address indexed user, uint256 indexed amount);

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
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // address of WBNB token
    address private constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // address of USDC token
    uint256 private constant LOCKING_PERIOD = 6 weeks;
    uint256 private constant SECS_IN_YEAR = 31536000;
    address private immutable s_feeWallet;

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
    uint256 private s_totalRewards; // total Rewards disbursed by the contract till now

    constructor(address _feeWallet, address _nftToken, address _rewardToken) Ownable(msg.sender) {
        s_feeWallet = _feeWallet;
        s_nftToken = IERC721(_nftToken);
        s_rewardToken = IERC20(_rewardToken);

        // add USDC as a valid currency
        s_validCurrencies[0] = WBNB;
        s_validCurrencies[1] = USDC;
    }

    // Externals

    function setPoolConfig(
        uint256[5] memory _APRs,
        uint256[5] memory _boostedAPRs,
        uint256[5] memory _boosterRewards,
        uint256[5] memory _badgeCosts,
        uint256[5] memory _badgePreReqs
    ) external onlyOwner {
        s_APRs = _APRs;
        s_boostedAPRs = _boostedAPRs;
        s_boosterRewards = _boosterRewards;
        s_badgeCosts = _badgeCosts;
        s_badgePreReqs = _badgePreReqs;
    }

    function stakeNFT(uint256 _quantity) external {
        // quant of NFTs to stake (ensure > 0) + owned by the owner
        // ensure that the user has sufficient badges to stake the tokens
        // add the rewards earned hither to the user's pending rewards to offset the effect of resetting the lastRewardTime

        //@explain this is to offset the effect of reinit the lastRewardTime for user
        // if user makes multiple stakes, and each time we reset the lastRewardTime to current ts; then
        // at the end during rewardClaim the timePeriod for staking would be current TS - lastRewardTs (when latest stake was made)
        // thereby nullifying the rewards accumulated on prev staked amts

        // transfer NFTs to the contract
        // update user's state (update level, badges)
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

    //@dev user can't stake multiple times i.e can't boost multiple times; they need to unstake first
    //q how to handle boosts at different levels?
    function boostLvl() external {
        // reverts if the user has no staked NFTs or is already boosted or lacks the balance
        // if not, the user has to stake the required AMT of reward tokens (defined for their current lvl) to boost their level
        // event Emitted to notify the indexers
        // locking period for teh user is updated ; also lastRewardTime and hence pending rewards are updated

        User memory user = s_users[msg.sender];
        if (user.stakedNFTs == 0) {
            revert SM_NotEnoughNFTBalance();
        }
        if (user.isBoosted) {
            revert SM_UserAlreadyBoosted();
        }

        uint256 userBalance = s_rewardToken.balanceOf(msg.sender);
        uint256 reqAmt = s_boosterRewards[user.currentLevel - 1];
        if (userBalance < reqAmt) {
            revert SM_NotEnoughProtocolTokens();
        } else {
            uint256 actualAmt = reqAmt - user.stakedRewardTokens;
            s_rewardToken.transferFrom(msg.sender, address(this), actualAmt);
            user.stakedRewardTokens += actualAmt;
            emit TokensStaked(msg.sender, reqAmt);
        }

        uint256 rewards = earned(msg.sender);
        user.pendingRewards += rewards;
        user.isBoosted = true;
        user.lastRewarded = block.timestamp;
        user.lockingPeriod = block.timestamp + LOCKING_PERIOD;

        s_users[msg.sender] = user;
        emit BoostedLvl(msg.sender, user.currentLevel);
    }

    function unstakeTokens(uint256 _quantity) external {
        // reverts if the user has no staked tokens or their locking period has not passed yet
        // check if they are alread boosted and
        User memory user = s_users[msg.sender];

        if (user.stakedRewardTokens < _quantity) {
            revert SM_NotEnoughProtocolTokens();
        }

        if (user.lockingPeriod > block.timestamp) {
            revert SM_LockingPeriodNotOver();
        }

        uint256 remainingTokens = user.stakedRewardTokens - _quantity;
        if (user.isBoosted) {
            if (s_boosterRewards[user.currentLevel - 1] > remainingTokens) {
                uint256 earnedRewards = earned(msg.sender);
                user.pendingRewards += earnedRewards;
                user.lastRewarded = block.timestamp;
                user.isBoosted = false;
            }
        }

        user.stakedRewardTokens = remainingTokens;
        if (user.stakedRewardTokens == 0) {
            user.lockingPeriod = 0;
        }
        s_users[msg.sender] = user;
        s_rewardToken.transfer(msg.sender, _quantity);

        emit TokensUnstaked(msg.sender, _quantity);
    }

    // param _level is the badge level to buy ; starts at 1
    function buyBadge(uint8 _level, uint8 _currency) external payable {
        // Buying badge logic

        // if the user has the badge for the level then they can't buy the badge for the same level
        // check if the user has required staked NFTs to warrant a badge purchase
        // check if the currenyc is a valid choice
        // use paymentExecutor to buy trasnfer the funds; if successufl add a badge to the user's profile

        User memory user = s_users[msg.sender];
        if (user.badges[_level - 1] == _level) {
            revert SM_BadgeAlreadyExists();
        }

        if (s_nftToken.balanceOf(msg.sender) < s_badgePreReqs[_level - 1]) {
            revert SM_NotEnoughNFTBalance();
        }

        address currency = s_validCurrencies[_currency];
        if (currency == address(0)) {
            revert SM_InvalidCurrency();
        }

        _executePayment(msg.sender, s_badgeCosts[_level - 1], currency);

        // badge added to the user's profile
        user.badges[_level - 1] = _level;
        // buying a new badge may change the user's level; NOT automatically tho!!
        //q revise logic for this
        _updateLevel(msg.sender);
        s_users[msg.sender] = user;

        emit BadgeBought(msg.sender, _level);
    }

    function claimRewards() external {
        // calcaulting total Rewrads (pending rewards + earned)
        // if the user is boosted then the those staked tokens are locked and won't be available for withdrawal
        // rewards are minted to the user (instead of trasnferred)
        uint256 totalRewards = calculateTotalRewards(msg.sender);

        s_rewardToken.mint(msg.sender, totalRewards);
        s_totalRewards += totalRewards;
        emit RewardsDisbursed(msg.sender, totalRewards);
    }

    // external setters

    function setAPRs(uint256[5] memory _APRs) external onlyOwner {
        s_APRs = _APRs;
    }

    function setBoostedAPRs(uint256[5] memory _boostedAPRs) external onlyOwner {
        s_boostedAPRs = _boostedAPRs;
    }

    function setBoosterRewards(uint256[5] memory _boostedRewards) external onlyOwner {
        s_boosterRewards = _boostedRewards;
    }

    function setBadgeCosts(uint256[5] memory _badgeCosts) external onlyOwner {
        s_badgeCosts = _badgeCosts;
    }

    function setBadgePreReqs(uint256[5] memory _badgePreReqs) external onlyOwner {
        s_badgePreReqs = _badgePreReqs;
    }

    // Internals

    //@param _amount is the cost of the badge
    function _executePayment(address _sender, uint256 _amount, address _currency) internal {
        // the feeWallet needs to be funded in protocol's token (in this case the reward token itself)
        // 3 ways
        // 1. user pays in WBNB
        // 2. user pays in USDC
        // 3. user pays in protocol's token

        if (_currency == WBNB) {
            address[] memory path = new address[](2);
            path[0] = WBNB;
            path[1] = USDC;

            uint256[] memory amounts = s_router.getAmountsOut(msg.value, path);

            if (_amount > amounts[1]) {
                revert SM_NotEnoughBalanceForBadgePurchase();
            }

            address[] memory swapPath = new address[](2);
            path[0] = WBNB;
            path[1] = USDC;
            path[2] = address(s_rewardToken);

            //swapExactETH takes in native tokens; hence the value: msg.value ; hence also the first token in swapPath is WBNB (native token for BNB chain)
            s_router.swapExactETHForTokens{value: msg.value}(_amount, swapPath, s_feeWallet, block.timestamp);
        } else if (_currency == USDC) {
            if (IERC20(USDC).balanceOf(_sender) < _amount) {
                revert SM_NotEnoughBalanceForBadgePurchase();
            }

            // trasnfer USDC from the sender to this contract; then swap USDC for protocol's token and fund the feeWallet
            IERC20(USDC).transferFrom(_sender, address(this), _amount);

            // approving the router to spend the USDC on behalf of the contract
            if (IERC20(USDC).allowance(address(this), ROUTER) < _amount) {
                IERC20(USDC).approve(ROUTER, type(uint256).max);
            }

            address[] memory path = new address[](2);
            path[0] = USDC;
            path[1] = address(s_rewardToken);
            s_router.swapExactTokensForTokens(_amount, 0, path, s_feeWallet, block.timestamp);
        } else {
            if (s_rewardToken.balanceOf(_sender) < _amount) {
                revert SM_NotEnoughBalanceForBadgePurchase();
            }
            s_rewardToken.transferFrom(_sender, s_feeWallet, _amount);
        }
    }

    function calculateTotalRewards(address _user) internal returns (uint256 totalRewards) {
        // returns the total rewards earned by the user
        // reverts if pendingRewards = 0 && stakedNFts = 0
        User memory user = s_users[_user];
        if (user.pendingRewards == 0 && user.stakedNFTs == 0) {
            revert SM_NotEligibleForRewards();
        }
        uint256 earnedRewards = earned(_user);
        totalRewards = user.pendingRewards + earnedRewards;
        if (totalRewards == 0) revert SM_NoRewardsAvailable();
        user.pendingRewards = 0;
        // if user has already unstaked all NFTs then stakedNFts would be 0
        // if the user still has NFTs staked then the lastRewarded time should be updated
        if (user.stakedNFTs == 0) {
            user.lastRewarded = 0;
        } else {
            user.lastRewarded = block.timestamp;
        }
        s_users[_user] = user;
    }

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

    function getAmtStaked(address _user) external view returns (uint256) {
        return s_users[_user].stakedNFTs;
    }

    function getStakedNFTs(address _user) external view returns (uint256[] memory) {
        return s_stakedIds[_user];
    }

    function getRouter() external view returns (address) {
        return ROUTER;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}
