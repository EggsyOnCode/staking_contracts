// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {StakingManager} from "src/Staking.sol";
// import {HelperConfig} from "./HelperConfig.s.sol";

contract Name is Script {
    // HelperConfig public helperConfig;

    function run() external returns (StakingManager) {
        address _sToken;
        address _rToken;

        vm.startBroadcast();
        StakingManager stakingManager = new StakingManager(_sToken, _rToken);
        vm.stopBroadcast();
        return stakingManager;
    }
}
