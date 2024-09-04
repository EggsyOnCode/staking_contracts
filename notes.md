# Staking Logic

- duration + finish time period for staking
- amt of rewards reserved fro rewards needs to be forwarded to the contract by the owner or given approval of
- everytime someone makes a state chaning tx like stake, withdraw, getReward we have to update the rewardPerTokenPerBlock, and accumulatorRewardIndex by calculating how many blocks it was from the lastTimeUpdated (last time a state changing tx was made)
- we also need to keep track of the reward_debt per user + how much they have staked in a mapping of UserInfo Struct
- reward_debt is updated everytime the user makes multiple deposits by the formula `reward_debt += _newAmt * updatedRewardAcculmulator`
- for the sake of precision, we have to use a precision multiplier for rewardAcc
- the algorithm seems unfair to HODLers who have been staking for a long time, and a whale could stake a hefty portion to reduce rewards per capita. (but since for the same time interval, the rewards for all (including the whale) are defreciating, there's no incentive for the whales to do this)
