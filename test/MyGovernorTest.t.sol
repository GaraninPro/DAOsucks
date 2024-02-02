// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    Box box;
    GovToken token;
    MyGovernor governor;
    TimeLock timeLock;

    address public constant VOTER = address(1);

    //////////////
    // ARRAYS///
    ///////////////
    address[] proposers;
    address[] executors;
    address[] targets; //addressesToCall

    bytes[] callDatas; //functionCalls
    uint256[] values;

    //////////////
    ////uint256//
    ////////////

    uint256 public constant MIN_DELAY = 3600; // 1hour - after a vote passes, you have 1 hour before you can enact
    uint256 public constant VOTING_DELAY = 1; // the term "voting delay" refers to the period that elapses between when a proposal is created and when the voting process begins. 1 block is 12 seconds.
    uint256 public constant VOTING_PERIOD = 50400;
    //uint256 public constant

    function setUp() public {
        token = new GovToken();
        token.mint(VOTER, 100e18);

        vm.startPrank(VOTER);

        token.delegate(VOTER); // we delegate voting power to VOTER with 100 tokens

        timeLock = new TimeLock(MIN_DELAY, proposers, executors);

        governor = new MyGovernor(token, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();

        bytes32 executorRole = timeLock.EXECUTOR_ROLE();

        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor)); // function from AccsessControl.sol
        timeLock.grantRole(executorRole, address(0)); // To zero address means to EVERyBody !!!

        timeLock.revokeRole(adminRole, VOTER); // Voter no longer admin of timeLock
        vm.stopPrank();
        box = new Box();
        box.transferOwnership(address(timeLock)); // So no timeLock can call functions with onlyOwner modifier
    }

    function testCanNotUpdateBoxWithoutGovernance() public {
        vm.expectRevert();

        box.setNumber(1);
    }
    /////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 777;

        string memory description = "Get a shield !!!";

        bytes memory encodedFunctionCall = abi.encodeWithSignature("setNumber(uint256)", valueToStore);

        callDatas.push(encodedFunctionCall);
        values.push(0);
        targets.push(address(box));

        // 1) Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, callDatas, description); //// Function from Igovernor

        console.log("Proposal state:", uint256(governor.state(proposalId))); // Pending

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal state:", uint256(governor.state(proposalId))); // Now supposed to be active

        // 2) Vote

        string memory reason = "Fuck knows !!!";
        // 0 = against  1 = yes  3 = abstain
        uint8 voteWay = 1;

        vm.prank(VOTER);

        governor.castVoteWithReason(proposalId, voteWay, reason); // Function from Igovernor

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proposal state:", uint256(governor.state(proposalId))); // Now supposed to be active

        // 3) Queue

        //Function to queue a proposal to the timelock.

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, callDatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4) Execute

        governor.execute(targets, values, callDatas, descriptionHash);

        assertEq(valueToStore, box.getNumber());
    }
}
