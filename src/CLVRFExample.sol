// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////////////////
            Imports
///////////////////////////////////*/
import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/*///////////////////////////////////
            Interfaces
///////////////////////////////////*/

/*///////////////////////////////////
            Libraries
///////////////////////////////////*/

/**
    *@title CL VRF Example
    *@notice Example of simple VRF usage
    *@notice Created to be used on the Chainlink Introduction Course
    *@author i3arba - 77 Educational Labs
    *@dev Do not use this contract in production
*/
contract CLVRFExample is VRFConsumerBaseV2Plus {

    /*///////////////////////////////////
            Type declarations
    ///////////////////////////////////*/
    ///@notice enum to ensure `state machine` pattern
    enum RaffleStatus{
        open,
        draw
    }

    RaffleStatus public status;

    ///@notice Struct to store the VRF requests info.
    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256 randomWord;
        uint256 prizeAmount;
        address winner;
    }


    /*///////////////////////////////////
                Variables
    ///////////////////////////////////*/
    ///@notice immutable variable to store the amount of gas allowed to be consumed to complete a request
    uint32 immutable i_callbackGasLimit;
    ///@notice variable to store the number of random number per request
    uint32 immutable i_numWords;
    ///@notice variable to store the gas lane to use, which specifies the maximum gas price to bump to.
    bytes32 immutable i_keyHash;
    ///@notice variable to store the subscription ID to be used by the protocol.
    uint256 immutable i_subscriptionId;

    ///@notice constant variable to store the number of confirmations need before a request can be fulfilled
    uint16 immutable REQUEST_CONFIRMATIONS = 3;
    ///@notice constant variable to remove magic numbers
    uint256 constant TICKET_PRICE = 1*10**16;
    uint256 constant ONE = 1;

    mapping(uint256 => RequestStatus) public s_requests;
    address[] s_ticketsSold;

    /*///////////////////////////////////
                Events
    ///////////////////////////////////*/
    ///@notice event emitted when a VRF request is initialized
    event CLVRFExample_RequestSent(uint256 requestId, uint256 numWords);
    ///@notice event emitted when a VRF request is fulfilled
    event CLVRFExample_RequestFulfilled(uint256 requestId, uint256 randomWords);
    ///@notice event emitted when a winner is selected
    event CLVRFExample_WinnerSelected(uint256 requestId, address winnerSelected);

    /*///////////////////////////////////
                Errors
    ///////////////////////////////////*/
    ///@notice error emitted when a VRF Request Id is invalid
    error CLVRFExample_InvalidRequestId(uint256 requestId);
    ///@notice error emitted when the amount of ether sent to the contract is incorrect
    error CLVRFExample_InvalidAmount(uint256 amountSent, uint256 amountExpected);
    ///@notice error emitted when drawWinner is called for a not fulfilled requestId
    error CLVRFExample_RequestNotFulfilled(uint256 requestId);
    ///@notice error emitted when drawWinner is called for an already fulfilled requestId
    error CLVRFExample_WinnerAlreadySelected(uint256 requestId, address winner);
    ///@notice error emitted when an user tries to buy a ticket while a draw happens
    error CLVRFExample_NotAbleToBuyTicketsDuringADraw();
    ///@notice error emitted when an user tries to claim a not finished draw
    error CLVRFExample_WinnerNotSelectedYet(uint256 requestId, address winner);
    ///@notice error emitted when a withdraw Fails
    error CLVRFExample_WithdrawFailed(bytes data);
    ///@notice error emitted when an user tries to double claim draw prize
    error CLVRFExample_PrizeAlreadyPaid(uint256 requestId);

    /*///////////////////////////////////
                Modifiers
    ///////////////////////////////////*/

    /*///////////////////////////////////
                Functions
    ///////////////////////////////////*/

    /*///////////////////////////////////
                constructor
    ///////////////////////////////////*/
    constructor(
        address _vrfCoordinator,
        uint32 _gasLimit,
        uint32 _numWords,
        bytes32 _keyHash,
        uint256 _subId
    ) VRFConsumerBaseV2Plus(_vrfCoordinator){
        i_callbackGasLimit = _gasLimit;
        i_numWords = _numWords;
        i_keyHash = _keyHash;
        i_subscriptionId = _subId;
    }

    /*///////////////////////////////////
            Receive&Fallback
    ///////////////////////////////////*/

    /*///////////////////////////////////
                external
    ///////////////////////////////////*/
    /**
        *@notice function for users to buy tickets
        *@param _tickets the number of tickets to be bought
        *@dev can only be executed on OPEN state.
    */
    function buyTickets(uint256 _tickets) external payable {
        if(msg.value != _tickets * TICKET_PRICE) revert CLVRFExample_InvalidAmount(msg.value, _tickets * TICKET_PRICE);
        if(status == RaffleStatus.draw) revert CLVRFExample_NotAbleToBuyTicketsDuringADraw();

        if(_tickets > ONE){
            for(uint256 i = 0; i < _tickets; ++i){
                s_ticketsSold.push(msg.sender);
            }
        } else {
            s_ticketsSold.push(msg.sender);
        }
    }

    /**
        *@notice function to start the VRF Request
        *@param _enableNativePayment if true, pays with native. If false, pays in link.
        *@dev can only be called by the owner
        * it will revert if the subscription is not funded
    */
    function requestRandomWords(
        bool _enableNativePayment
    ) external onlyOwner returns (uint256 requestId_) {

        requestId_ = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: i_numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: _enableNativePayment
                    })
                )
            })
        );

        status = RaffleStatus.draw;

        s_requests[requestId_] = RequestStatus({
            fulfilled: false,
            exists: true,
            randomWord: 0,
            prizeAmount: 0,
            winner: address(0)
        });


        emit CLVRFExample_RequestSent(requestId_, i_numWords);
    }

    /**
        *@notice function to select the winner using the random number requested
        *@param _requestId the request to be finalized
        *@dev anyone can call this function
    */
    function drawWinner(uint256 _requestId) external {
        RequestStatus memory request = s_requests[_requestId];
        if(!request.exists) revert CLVRFExample_InvalidRequestId(_requestId);
        if(!request.fulfilled) revert CLVRFExample_RequestNotFulfilled(_requestId);
        if(request.winner == address(0)) revert CLVRFExample_WinnerAlreadySelected(_requestId, request.winner);

        uint256 numberSelected = request.randomWord % s_ticketsSold.length;
        address winnerSelected = s_ticketsSold[numberSelected];

        s_requests[_requestId].winner = winnerSelected;
        s_requests[_requestId].prizeAmount = address(this).balance;
        delete s_ticketsSold;
        status = RaffleStatus.open;

        emit CLVRFExample_WinnerSelected(_requestId, winnerSelected);
    }

    /**
        *@notice function for winners to withdraw their prizes
        *@param _requestId the draw Id to be claimed
        *@dev anyone can call the function, but the winner must receive the prize amount
    */
    function winnerWithdraw(uint256 _requestId) external {
        RequestStatus memory request = s_requests[_requestId];
        if(request.winner == address(0)) revert CLVRFExample_WinnerNotSelectedYet(_requestId, request.winner);
        if(request.prizeAmount == 0) revert CLVRFExample_PrizeAlreadyPaid(_requestId);

        s_requests[_requestId].prizeAmount = 0;

        (bool success, bytes memory data ) = request.winner.call{value: request.prizeAmount}("");
        if(!success) revert CLVRFExample_WithdrawFailed(data);
    }

    /*///////////////////////////////////
                public
    ///////////////////////////////////*/

    /*///////////////////////////////////
                internal
    ///////////////////////////////////*/
    /**
        *@notice standard internal function for requests fulfillment
        *@param _requestId the request to be fulfilled
        *@param _randomWords the array with the amount of numbers requested
    */
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        RequestStatus storage request = s_requests[_requestId];
        if(!request.exists) revert CLVRFExample_InvalidRequestId(_requestId);

        request.randomWord = _randomWords[0];
        request.fulfilled = true;

        emit CLVRFExample_RequestFulfilled(_requestId, _randomWords[0]);
    }

    /*///////////////////////////////////
                private
    ///////////////////////////////////*/

    /*///////////////////////////////////
            View & Pure
    ///////////////////////////////////*/
    /**
        *@notice getter function to return a specific request status
        *@param _requestId the request Id to be returned
        *@return request_ the whole RequestStatus structure
    */
    function getRequestStatus(
        uint256 _requestId
    ) external view returns (RequestStatus memory request_) {
        request_ = s_requests[_requestId];
        if(!request_.exists) revert CLVRFExample_InvalidRequestId(_requestId);
    }
}
