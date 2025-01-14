// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";

contract RewardDistributor {

    address public admin;
    
    uint256 public protocolEpochSize;
    uint256 public totalRecordedEpochs;
    uint256 public currentEpoch;
    uint256 public lifetimeStartTime;

    mapping(address => NodeProfile) public nodeProfile;
    mapping(uint256 => Epoch) public epochInformation;

    struct NodeProfile {
        bool status;
        uint256 startEpoch;
        uint256 startTime;
        uint256 endEpoch;
        uint256 endTime;
        uint256 compute;
        uint256 rewardsClaimed; 
    }

    struct Epoch {
        uint256 startTime;
        uint256 endTime;
        uint256 aggregateRate;
        uint256 ratePerEpoch;
    }

    constructor(
        uint256 _epochSize,
        uint256 _rewardRate
    ) {
        admin = msg.sender;
        lifetimeStartTime = block.timestamp;
        protocolEpochSize = _epochSize;
        epochInformation[0].startTime = block.timestamp;
        epochInformation[0].aggregateRate = 0;
        epochInformation[0].ratePerEpoch = _rewardRate;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    function updateRewardRate(uint256 _newRate) public onlyAdmin {
        updateProtocolForNewRate(_newRate);
    }

    function openNodeProfile(address _newNode, uint256 _computeLoad) public onlyAdmin {
        require(!nodeProfile[_newNode].status, "Node address already active.");
        nodeProfile[_newNode].status = true;
        nodeProfile[_newNode].startEpoch = currentEpoch;
        nodeProfile[_newNode].compute = _computeLoad;
        nodeProfile[_newNode].startTime = block.timestamp;
    }

    function closeNodeProfile(address _closeNode) public onlyAdmin {
        require(nodeProfile[_closeNode].status, "Node address already inactive.");
        nodeProfile[_closeNode].status = false;
        nodeProfile[_closeNode].endEpoch = currentEpoch;
        nodeProfile[_closeNode].endTime = block.timestamp;
        claimReward(_closeNode);
    }

    function claimReward(address _node) public returns(uint256 rewardSize) {
        NodeProfile memory node_ = nodeProfile[_node];
        uint256 effectiveEndTime_ = node_.status ? block.timestamp : node_.endTime;
        rewardSize = calculateUserReward(_node, effectiveEndTime_);
        uint256 availableToClaim = rewardSize - node_.rewardsClaimed;
        nodeProfile[_node].rewardsClaimed += availableToClaim;
    }

    function updateProtocolForNewRate(uint256 _newRate) internal {
        epochInformation[currentEpoch].endTime = block.timestamp;
        Epoch memory currentEpoch_ = epochInformation[currentEpoch];
        uint256 totalRecordedEpochsExp_ = 
            (block.timestamp - currentEpoch_.startTime) * 1e18 / protocolEpochSize;
        uint256 totalRecordedEpochs_ = totalRecordedEpochsExp_ / 1e18 + totalRecordedEpochs;
        totalRecordedEpochs = totalRecordedEpochs_;
        currentEpoch++;
        epochInformation[currentEpoch].startTime = block.timestamp;
        epochInformation[currentEpoch].ratePerEpoch = _newRate;
        epochInformation[currentEpoch].aggregateRate = 
            currentEpoch_.aggregateRate 
            + currentEpoch_.ratePerEpoch 
                * (currentEpoch_.endTime - currentEpoch_.startTime) 
                / protocolEpochSize;
    }

    function calculateUserReward(address _node, uint256 _nodeEndTime) internal view returns(uint256 reward) {
        NodeProfile memory node_ = nodeProfile[_node];
        Epoch memory startEpoch_ = epochInformation[node_.startEpoch];
        Epoch memory endingEpoch_ = epochInformation[node_.endEpoch];
        Epoch memory currentEpoch_ = epochInformation[currentEpoch];

        //Compute average reward per compute unit over lifetime contribution
        uint256 totalAggRate_;
        if(_nodeEndTime < currentEpoch_.startTime) {
            totalAggRate_ = (
                endingEpoch_.aggregateRate
                + endingEpoch_.ratePerEpoch 
                    * (_nodeEndTime - endingEpoch_.startTime)
                    / (protocolEpochSize)
            ) * 1e18;
        } else {
            totalAggRate_ = (
                currentEpoch_.aggregateRate
                + currentEpoch_.ratePerEpoch
                    * (_nodeEndTime - currentEpoch_.startTime) 
                    / (protocolEpochSize)
            ) * 1e18;
        }
        uint256 baseStartEndTime_ = startEpoch_.endTime == 0 ? block.timestamp : startEpoch_.endTime;
        uint256 startingAggRate_ = 
            (
                startEpoch_.aggregateRate * 1e18
                + startEpoch_.ratePerEpoch 
                    * (
                        1e18 
                        - 1e18 
                            * (baseStartEndTime_ - node_.startTime)
                            / (baseStartEndTime_ - startEpoch_.startTime)
                    ) * ((baseStartEndTime_ - startEpoch_.startTime) / protocolEpochSize)
            );
        reward = (totalAggRate_ - startingAggRate_) * nodeProfile[_node].compute;
    }
}
