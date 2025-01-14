// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RewardDistributor} from "../src/RewardDistributor.sol";

contract RewardDistributorTest is Test {
    /** 
    Tests: 
    1) Protocol configuration on set up - DONE 
    2) Open a node - DONE 
    3) Close a node - DONE 
    4) Update protocol reward rate (constant) - DONE 
    5) Compute node reward rate (constant) - DONE 
    6) Update protocol reward rate (dynamic) - DONE 
    7) Compute node reward rate (dynamic) - DONE
    8) Multiple nodes, multiple rates (dynamic) - DONE
    9) Multiple nodes, multiple rates, post node closure claim (dynamic) - DONE
    */

    RewardDistributor rewardDist;
    address adminAddress = address(0xABCD);
    address node1 = address(0x1234);
    address node2 = address(0x5678);

    function setUp() public {
        vm.startPrank(adminAddress);
        rewardDist = new RewardDistributor(
            100,
            10
        );
        vm.stopPrank();

        //Test for proper admin
        address actualAdmin = rewardDist.admin();
        assertEq(actualAdmin, adminAddress, "Admin should match the adminAddress");

        //Test reward setup 
        assertEq(rewardDist.lifetimeStartTime(), block.timestamp, "lifetimeStartTime failed to config.");
        assertEq(rewardDist.protocolEpochSize(), 100, "protocolEpochSize failed to config.");
        (
            uint256 _startTime,
            uint256 _endTime, 
            uint256 _aggregateAverageRate,
            uint256 _ratePerEpoch
        ) = rewardDist.epochInformation(0);
        assertEq(_startTime, block.timestamp, "Epoch 0 start time failed to config.");
        assertEq(_aggregateAverageRate, 0, "Epoch 0 agg rate failed to config.");
        assertEq(_ratePerEpoch, 10, "Epoch 0 rate per epoch failed to config.");
    }

    function testOpenNodeProfile() public {
        //Test non-admin call
        vm.expectRevert("Not admin");
        rewardDist.openNodeProfile(node1, 2);

        //Test admin call
        vm.startPrank(adminAddress);
        uint256 openTime = block.timestamp;
        skip(200);
        rewardDist.openNodeProfile(node1, 2);
        vm.stopPrank();

        //Test node1 active
        (
            bool status, 
            uint256 startEpoch_,
            uint256 startTime_, 
            ,
            ,
            uint256 compute_,

        ) = rewardDist.nodeProfile(node1);
        assertTrue(status, "node should be active");
        assertEq(startEpoch_, 0, "startEpoch_ improperly set");
        assertEq(startTime_, openTime + 200, "startTime_ improperly set");
        assertEq(compute_, 2, "compute_ improperly set");
    }

    function testCloseNodeProfile() public {
        //Open node1
        vm.startPrank(adminAddress);
        uint256 openTime = block.timestamp;
        skip(200);
        rewardDist.openNodeProfile(node1, 2);
        vm.stopPrank();

        //Test non-admin closure
        vm.expectRevert("Not admin");
        rewardDist.closeNodeProfile(node1);

        //Test admin closure
        vm.startPrank(adminAddress);
        skip(200);
        rewardDist.closeNodeProfile(node1);
        vm.stopPrank();

        (
            uint256 _startTime,
            uint256 _endTime, 
            uint256 _aggregateAverageRate,
            uint256 _ratePerEpoch
        ) = rewardDist.epochInformation(0);
        //Test node closure operations 
        (
            bool status, 
            uint256 startEpoch_,
            uint256 startTime_, 
            uint256 endEpoch_,
            uint256 endTime_,
            uint256 compute_,
            uint256 rewardsClaimed_
        ) = rewardDist.nodeProfile(node1);
        assertFalse(status, "node1 should be inactive.");
        assertEq(startTime_, openTime + 200, "startTime_ should be set on opening a node profile");
        assertEq(startEpoch_, 0, "startEpoch_ incorrect");
        assertEq(endTime_, openTime + 400, "endTime should be set when closing a node profile");
        assertEq(endEpoch_, 0, "startEpoch_ incorrect");
        assertEq(rewardsClaimed_, 40e18, "rewardEarned incorrectly calculated");
    }

    function testUpdateRewardRate() public {
        assertTrue(rewardDist.protocolEpochSize() > 0, "Epoch size should not be 0");
        uint256 startTimestamp = block.timestamp;
        skip(1000);
        // Only admin can call
        vm.expectRevert("Not admin");
        rewardDist.updateRewardRate(10);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(20);
        vm.stopPrank();

        // Check old epoch metrics
        (
            ,
            uint256 oldEpochEndTime,
            uint256 oldAggregateAverageRate,
            uint256 oldRatePerEpoch
        ) = rewardDist.epochInformation(0);
        assertEq(oldEpochEndTime, startTimestamp + 1000, "Incorrectly recorded epoch end time");
        assertEq(oldAggregateAverageRate, 0, "Incorrectly recorded epoch agg rate");
        assertEq(oldRatePerEpoch, 10, "Incorrectly recorded epoch flat rate");

        // Check new epoch metrics
        (
            uint256 newEpochStartTime,
            uint256 newEpochEndTime,
            uint256 newAggregateAverageRate,
            uint256 newRatePerEpoch
        ) = rewardDist.epochInformation(1);
        assertEq(newEpochStartTime, startTimestamp + 1000, "Epoch length incorrectly recorded");
        assertEq(newAggregateAverageRate, 100, "Aggregate average rate incorrectly recorded");
        assertEq(newRatePerEpoch, 20, "Rate per epoch incorrectly recorded");

        assertEq(rewardDist.totalRecordedEpochs(), 10, "Incorrect totalRecordedEpochs");

        skip(1000);
        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(30);
        vm.stopPrank();

        (
            newEpochStartTime,
            newEpochEndTime,
            newAggregateAverageRate,
            newRatePerEpoch
        ) = rewardDist.epochInformation(2);
        assertEq(newAggregateAverageRate, 300, "Aggregate average rate incorrectly recorded");
        assertEq(newRatePerEpoch, 30, "Rate per epoch incorrectly recorded");

        assertEq(rewardDist.totalRecordedEpochs(), 20, "Incorrect totalRecordedEpochs");

        skip(1000);
        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(10);
        vm.stopPrank();

        (
            newEpochStartTime,
            newEpochEndTime,
            newAggregateAverageRate,
            newRatePerEpoch
        ) = rewardDist.epochInformation(3);
        assertEq(newAggregateAverageRate, 600, "Aggregate average rate incorrectly recorded");
        assertEq(newRatePerEpoch, 10, "Rate per epoch incorrectly recorded");

        assertEq(rewardDist.totalRecordedEpochs(), 30, "Incorrect totalRecordedEpochs");
    }

    function testClaimReward() public {
        // Open node1
        vm.startPrank(adminAddress);
        skip(200);
        rewardDist.openNodeProfile(node1, 2);
        vm.stopPrank();
        skip(200);

        // Claim rewards from node1
        vm.startPrank(node1);
        uint256 rewardSize = rewardDist.claimReward(node1);
        vm.stopPrank();

        // Check the node1's rewardEarned
        (
            uint256 epochStartTime,
            uint256 epochEndTime,
            uint256 aggregateAverageRate,
            uint256 ratePerEpoch
        ) = rewardDist.epochInformation(0);
        (
            bool status, 
            uint256 startEpoch_,
            uint256 startTime_, 
            uint256 endEpoch_,
            uint256 endTime_,
            uint256 compute_,
            uint256 rewardsClaimed_
        ) = rewardDist.nodeProfile(node1);
        assertNotEq(block.timestamp, startTime_, "No work done by node.");
        assertEq(epochStartTime, startTime_ - 200, "Start time incorrect.");
        assertGt(rewardsClaimed_, 0, "Reward should be greater than zero after 200 seconds of work.");
    }

    function testDynamicRewardRate() public {
        vm.startPrank(adminAddress);
        skip(200);
        rewardDist.openNodeProfile(node1, 2);
        vm.stopPrank();
        skip(200);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(20);
        vm.stopPrank();

        skip(1000);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(30);
        vm.stopPrank();

        skip(1000);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(10);
        vm.stopPrank();

        vm.startPrank(node1);
        uint256 rewardSize = rewardDist.claimReward(node1);
        vm.stopPrank();
        assertEq(rewardSize, 1040e18, "rewardSize improperly calculated");
    }

    function testMultipleNodesDynamicsRewards() public {
        vm.startPrank(adminAddress);
        rewardDist.openNodeProfile(node1, 2);
        vm.stopPrank();
        skip(200);

        vm.startPrank(adminAddress);
        rewardDist.openNodeProfile(node2, 2);
        vm.stopPrank();
        skip(200);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(20);
        vm.stopPrank();

        skip(1000);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(30);
        vm.stopPrank();

        vm.startPrank(node1);
        uint256 rewardSize1 = rewardDist.claimReward(node1);
        vm.stopPrank();

        assertEq(rewardSize1, 480e18, "rewardSize improperly calculated");

        vm.startPrank(node2);
        uint256 rewardSize2 = rewardDist.claimReward(node2);
        vm.stopPrank();

        assertEq(rewardSize2, 440e18, "rewardSize improperly calculated");
    }

    function testMultipleNodesDynamicsRewardsPostClosure() public {
        vm.startPrank(adminAddress);
        rewardDist.openNodeProfile(node1, 2);
        vm.stopPrank();
        skip(200);

        vm.startPrank(adminAddress);
        rewardDist.openNodeProfile(node2, 2);
        vm.stopPrank();
        skip(200);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(20);
        vm.stopPrank();

        skip(1000);

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(30);
        vm.stopPrank();

        vm.startPrank(adminAddress);
        rewardDist.closeNodeProfile(node1);
        vm.stopPrank();

        vm.startPrank(adminAddress);
        rewardDist.closeNodeProfile(node2);
        vm.stopPrank();

        vm.startPrank(adminAddress);
        rewardDist.updateRewardRate(10);
        vm.stopPrank();

        skip(1000);

        vm.startPrank(node1);
        uint256 rewardSize1 = rewardDist.claimReward(node1);
        vm.stopPrank();

        vm.startPrank(node2);
        uint256 rewardSize2 = rewardDist.claimReward(node2);
        vm.stopPrank();

        assertEq(rewardSize1, 480e18, "rewardSize improperly calculated");
        assertEq(rewardSize2, 440e18, "rewardSize improperly calculated");
    }
}
