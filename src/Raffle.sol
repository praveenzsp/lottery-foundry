// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A simple Raffle contract
 * @author praveen zsp
 * @notice This contract is for sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughETHSent();
    error Raffle__TransferFailed();
    error Raffle__AuctionClosed();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 players_length,
        uint256 raffle_state
    );

    /** Type Declarations */
    enum RaffleState {
        OPEN,
        CLOSED
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_OF_WORDS = 1;

    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    uint256 private immutable i_interval; // duration of lottery in seconds
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint32 private immutable i_callbackGasLimit;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint256 private s_lastTimestamp;
    address payable s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        uint32 callbackGasLimit,
        bytes32 gasLane,
        uint64 subscriptionId
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimestamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_callbackGasLimit = callbackGasLimit;
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable returns(uint256, address) {
        // external bcuz more gas effecient
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHSent(); // custom errors are more gas effecient than require()
        }

        if (s_raffleState != RaffleState.OPEN) {
            // can only enter the raffle if it is open
            revert Raffle__AuctionClosed();
        }
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
        return (msg.value, msg.sender);
    }
   
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = block.timestamp - s_lastTimestamp >= i_interval;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        upkeepNeeded = (timeHasPassed && hasBalance && hasPlayers && isOpen);
        return (upkeepNeeded, "0x0");
    }

    // get a random number
    // pick a winner using that random number
    // Be automatically called

    function performUpkeep(bytes calldata /* performData */) external {
        // this need to be called automatically - so use chainlink automation
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CLOSED; // while picking the winner, raffle must be closed

        uint256 requestId = i_vrfCoordinator.requestRandomWords( // sending req to chainlink node to get the random number
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_OF_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        // it will get the random number once the req is made
        uint256 /**requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // checks
        //Effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winnerAddress = s_players[indexOfWinner];
        s_recentWinner = winnerAddress;
        s_raffleState = RaffleState.OPEN; // setting the raffle open once the winner is picked
        s_players = new address payable[](0); // resetting the players array once the winner gets picked
        s_lastTimestamp = block.timestamp;
        emit PickedWinner(winnerAddress);

        //Interactions
        (bool success, ) = winnerAddress.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** getter functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState) {
        return s_raffleState;
    }

    function getPlayersArray() external view returns (address payable[] memory) {
        return s_players;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }
    // function getTimestamp() external view returns (uint256) {
    //     return block.timestamp;
    // }
    function getRecentWinner() external view returns(address){
        return s_recentWinner;
    }
}

//  Design patterns

//  CEI - checks Effects and interactions

//  checks - checking whether to revert or not right after entering a function. bcuz if we revert due to some conditions just after entering a function we can save up a lot of gas bcuz we dont need to execute all the unnecessary operations.

//  Effects - operations which will gave an effect on our own contract.

//  Interactions - this is where we interact with other contracts.

//  It is better to follow this design pattern
