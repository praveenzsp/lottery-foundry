// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HeplerConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    uint32 callbackGasLimit;
    bytes32 gasLane;
    uint64 subscriptionId;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (entranceFee, interval, vrfCoordinator, callbackGasLimit, gasLane, subscriptionId, link, ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testPlayerFeeMoreThanEntranceFee() public {
        (uint256 userFee,) = raffle.enterRaffle{value: 0.01 ether}();
        assert( userFee>= entranceFee);
    }

    function testRaffleIsOpenToEnter() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testPlayersArrayIsUpdating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value : 1 ether}();
        address payable[] memory playersArray = raffle.getPlayersArray();
        address recentlyAddedPlayer = playersArray[playersArray.length-1];
        // console.logAddress(PLAYER);
        assert(PLAYER == recentlyAddedPlayer);
    }

    // function testTimeHasPassed() public {
    //     vm.warp(block.timestamp+interval);
    //     assert(block.timestamp - raffle.getLastTimeStamp() >= interval);
    // }

    function testEmitEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle)) ;
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value :entranceFee }();

    }

    function testCantEnterWhenRaffleIsClosed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value : entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number+1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__AuctionClosed.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value : entranceFee}(); 
    }

    function testCheckupkeepReturnsFalseWhenItHasNoBalance() public {
        // arrange
        vm.warp(block.timestamp+interval+1);
        vm.roll(block.number+1);

        // act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        //assert
        assertFalse(upkeepNeeded);
    }

    function testCheckupkeepReturnsFalseWhenRaffleIsNotOpen() public {
        // arrange
        vm.warp(block.timestamp+interval+1);
        vm.roll(block.number+1);
        vm.prank(PLAYER);
        raffle.enterRaffle{value : entranceFee}();
        raffle.performUpkeep(""); 

        // act
        (bool upkeeNeeded,) = raffle.checkUpkeep("");

        // assert
        assertFalse(upkeeNeeded);
    }

    function testCheckupkeepReturnsFalseWhenTimeHasNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.roll(block.number+1);
        
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assertFalse(upkeepNeeded);
    }

    function testCheckupkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.roll(block.number+1);
        vm.warp(block.timestamp+interval+1);
        
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    function testPerformUpkeepRunsIfCheckupkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.roll(block.number+1);
        vm.warp(block.timestamp+interval+1);

        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckupkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, raffleState )); 
        raffle.performUpkeep("");
    }

    modifier hasBalanceAndTimeHasPassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value : entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number+1);
        _;
    }

    modifier skipFork() {
        if(block.chainid!=31337){
            return;
        }
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestedRaffleWinnerEvent() public hasBalanceAndTimeHasPassed {
        vm.recordLogs();
        raffle.performUpkeep(""); // emittinf the event in the performupkeep 
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 reqId = entries[1].topics[1];

        Raffle.RaffleState rstate = raffle.getRaffleState();

        assert(uint256(reqId) > 0);
        assert(uint256(rstate) == 1);
    }

    function testFulfillrandomWordsRunsAfterPerformUpkeep(uint256 randomRequestId) public skipFork hasBalanceAndTimeHasPassed {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksWinnerAndSendsMoney() hasBalanceAndTimeHasPassed public skipFork  {

         for(uint256 i = 1; i<=5; i++){
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);

            raffle.enterRaffle{value : entranceFee}();
         }

         vm.recordLogs();
         raffle.performUpkeep(""); // emitting the event in the performupkeep 
         Vm.Log[] memory entries = vm.getRecordedLogs();
         bytes32 requestId = entries[1].topics[1];

         VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

         uint256 previousTimestamp = raffle.getLastTimeStamp();

         assert(uint256(raffle.getRaffleState())==0);
         assert(raffle.getRecentWinner() != address(0));
         assert(raffle.getPlayersArray().length==0);
        //  assert(previousTimestamp < raffle.getLastTimeStamp());

        //  vm.expectEmit(true, false, false, false, address(raffle));
        //  emit PickedWinner(address(raffle.getRecentWinner()));
        //  VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assert(raffle.getRecentWinner().balance == (STARTING_USER_BALANCE+(5*entranceFee)));

        

    }
}

