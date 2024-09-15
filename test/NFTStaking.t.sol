// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {NFTStakingManager} from "src/GamifiedNFTStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {IERC721} from "src/interfaces/IERC721.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRouter} from "src/interfaces/IRouter.sol";

contract NftStakingTest is Test {
    NFTStakingManager public _stakingManager;
    ERC20Mock public _rewardToken;
    IERC721 public _nftToken;

    function setUp() external {
        // reward token depl
        _rewardToken = new ERC20Mock("Reward Token", "RWD", address(this), 1000);

        //nft token depl
        _stakingManager = new NFTStakingManager(address(_rewardToken), address(_nftToken));
    }
}
