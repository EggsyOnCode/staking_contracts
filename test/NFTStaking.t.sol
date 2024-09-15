// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {NFTStakingManager} from "src/GamifiedNFTStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MyNFT} from "./mocks/Mock721.sol";
import {IERC721} from "src/interfaces/IERC721.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {IUniswapV2Factory} from "src/interfaces/IRouter.sol";

contract NftStakingTest is Test {
    NFTStakingManager public _stakingManager;
    ERC20Mock public _rewardToken;
    MyNFT public _nftToken;
    IERC20 public _usdc;
    address public USER_1 = makeAddr("user1");
    address public USER_2 = makeAddr("user2");
    uint256 constant PRE_MINTED_NFTS = 10;
    uint256 constant USER_USDC = 100;
    uint256 bscFork;
    string private BSC_RPC = "https://bsc-rpc.publicnode.com";
    // on bsc
    address public UNI_FACT = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address private constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // address of Uniswap Router

    function setUp() external {
        // forking BSC
        bscFork = vm.createFork(BSC_RPC);
        // mock usd
        _usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);

        vm.selectFork(bscFork);

        // reward token depl
        _rewardToken = new ERC20Mock("Reward Token", "RWD", address(this), 100_000);

        //nft token depl
        _nftToken = new MyNFT("https://myapi.com/api/", address(_usdc));

        // staking manager depl
        _stakingManager = new NFTStakingManager(address(this), address(_nftToken), address(_rewardToken));

        // mint some nfts
        _nftToken.premintNFTs(USER_1, PRE_MINTED_NFTS);
        _nftToken.premintNFTs(USER_2, PRE_MINTED_NFTS);

        // approve staking manager to transfer nfts
        vm.prank(USER_1);
        _nftToken.setApprovalForAll(address(_stakingManager), true);

        vm.prank(USER_2);
        _nftToken.setApprovalForAll(address(_stakingManager), true);

        //fund USDC to users
        _usdc.mint(address(this), 100_000);
        _usdc.transfer(USER_1, 100);
        _usdc.transfer(USER_2, 100);

        // setting up pool config
        uint256[5] memory APRs;
        APRs[0] = 15_000 ether;
        APRs[1] = 17_500 ether;
        APRs[2] = 20_000 ether;
        APRs[3] = 22_500 ether;
        APRs[4] = 25_000 ether;

        uint256[5] memory boostedAPRs;
        boostedAPRs[0] = 17_500 ether;
        boostedAPRs[1] = 20_000 ether;
        boostedAPRs[2] = 22_500 ether;
        boostedAPRs[3] = 25_000 ether;
        boostedAPRs[4] = 27_500 ether;

        uint256[5] memory boostedRewards;
        boostedRewards[0] = 12_500 ether;
        boostedRewards[1] = 37_500 ether;
        boostedRewards[2] = 62_500 ether;
        boostedRewards[3] = 87_500 ether;
        boostedRewards[4] = 125_000 ether;

        uint256[5] memory badgeCosts;
        badgeCosts[0] = 62.5 ether;
        badgeCosts[1] = 187.5 ether;
        badgeCosts[2] = 312.5 ether;
        badgeCosts[3] = 437.5 ether;
        badgeCosts[4] = 625 ether;

        uint256[5] memory badgePreReq;
        badgePreReq[0] = 5;
        badgePreReq[1] = 15;
        badgePreReq[2] = 25;
        badgePreReq[3] = 35;
        badgePreReq[4] = 50;

        _stakingManager.setPoolConfig(APRs, boostedAPRs, boostedRewards, badgeCosts, badgePreReq);

        // Initialize Uniswap Factory and Router
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(UNI_FACT);
        IRouter uniswapRouter = IRouter(ROUTER); // replace with correct router address

        // Deploy the liquidity pool setup contract
        LiquidityPoolSetup liquidityPoolSetup =
            new LiquidityPoolSetup(uniswapFactory, uniswapRouter, _usdc, IERC20(address(_rewardToken)));

        uint256 usdcAmount = 1000 * 1e18; // Example amount of USDC
        uint256 rewardTokenAmount = usdcAmount * 5; // Amount of reward tokens to match 1 USDC = 5 Reward Tokens

        // Approve and add liquidity
        _usdc.approve(address(liquidityPoolSetup), usdcAmount);
        _rewardToken.approve(address(liquidityPoolSetup), rewardTokenAmount);

        liquidityPoolSetup.createAndAddLiquidity(usdcAmount, rewardTokenAmount);
    }

    function buyBadgeAtLevelX(uint256 _lvl) public {
        vm.selectFork(bscFork);

        vm.prank(USER_1);
        _stakingManager.buyBadge(uint8(_lvl), 1);

        vm.prank(USER_2);
        _stakingManager.buyBadge(uint8(_lvl), 1);
    }

    function testStakeAtLvlX() public {
        vm.selectFork(bscFork);

        buyBadgeAtLevelX(1);
        // stake nfts
        vm.prank(USER_1);
        _stakingManager.stakeNFT(3);

        vm.prank(USER_2);
        _stakingManager.stakeNFT(3);

        // check staked nfts
        assertEq(_stakingManager.getStakedNFTs(USER_1).length, 3);
        assertEq(_stakingManager.getStakedNFTs(USER_2).length, 3);
    }
}

contract LiquidityPoolSetup {
    IUniswapV2Factory public factory;
    IRouter public router;
    IERC20 public usdc;
    IERC20 public rewardToken;

    constructor(IUniswapV2Factory _factory, IRouter _router, IERC20 _usdc, IERC20 _rewardToken) {
        factory = _factory;
        router = _router;
        usdc = _usdc;
        rewardToken = _rewardToken;
    }

    function createAndAddLiquidity(uint256 amountUsdc, uint256 amountRewardToken) external {
        address pair = factory.createPair(address(usdc), address(rewardToken));
        require(pair != address(0), "Failed to create pair");

        usdc.transferFrom(msg.sender, address(this), amountUsdc);
        rewardToken.transferFrom(msg.sender, address(this), amountRewardToken);

        usdc.approve(address(router), amountUsdc);
        rewardToken.approve(address(router), amountRewardToken);

        // Adding liquidity
        router.addLiquidity(
            address(usdc),
            address(rewardToken),
            amountUsdc,
            amountRewardToken,
            amountUsdc,
            amountRewardToken,
            msg.sender,
            block.timestamp + 15 minutes
        );
    }
}
