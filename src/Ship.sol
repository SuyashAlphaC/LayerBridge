//SPDX-License-Identifier:MIT


pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from  "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Ship
 * @dev Individual ship contract that handles multiple tokens, CCIP transfer and automation
 * Works on both source and destination chains, uses native tokens for CCIP fees
 */
// Removed CCIPReceiver from inheritance, as this contract will no longer receive CCIP messages
// on the destination chain. It will only send.
contract Ship is
    OwnerIsCreator,
    ReentrancyGuard,
    AutomationCompatibleInterface
{
    IRouterClient private immutable I_ROUTER;

    // --- NEW: Address of the ShipReceiver contract on the destination chain ---
    address public immutable DESTINATION_SHIP_RECEIVER;

    // Ship parameters
    address public immutable CREATOR;
    uint64 public immutable DESTINATION_CHAIN_SELECTOR;
    uint8 public immutable CAPACITY;
    uint256 public immutable CREATED_AT;

    // Ship state
    uint8 public currentPassengers;
    bool public isLaunched;
    // isReceived and isDistributed are no longer needed here as the destination contract handles it
    // bool public isReceived;
    // bool public isDistributed;
    bytes32 public ccipMessageId;
    uint256 public collectedFees; // Native tokens collected for CCIP

    // Token tracking
    address[] public supportedTokens;
    mapping(address => bool) public isTokenSupported;
    mapping(address => uint256) public totalTokenAmounts;

    // Passenger data
    // Struct Passenger definition can be removed if not directly used here (it's internal to original Ship logic)
    // struct Passenger {
    //     address addr;
    //     mapping(address => uint256) tokenAmounts; // token => amount
    // }

    address[] public passengers;
    mapping(address => uint256) public passengerIndex;
    mapping(address => bool) public isPassenger;
    mapping(address => mapping(address => uint256))
        public passengerTokenAmounts; // passenger => token => amount

    // Fee structure
    uint256 public constant BASE_FEE = 0.001 ether; // Base fee per passenger
    uint256 public constant TOKEN_FEE = 0.0005 ether; // Additional fee per token type

    // Events
    event PassengerBoarded(
        address indexed passenger,
        address[] tokens,
        uint256[] amounts,
        uint8 passengerCount
    );
    event ShipLaunched(
        bytes32 indexed messageId,
        address[] tokens,
        uint256[] totalAmounts
    );
    event CCIPFeePaid(uint256 feeAmount);
    // ShipReceived, TokensDistributed, DistributionCompleted are now emitted by ShipReceiver
    // event ShipReceived(bytes32 indexed messageId, address[] tokens, uint256[] totalAmounts);
    // event TokensDistributed(address indexed recipient, address[] tokens, uint256[] amounts);
    // event DistributionCompleted(bytes32 indexed messageId);
    event TokenAdded(address indexed token);

    // Errors
    error ShipFull();
    error AlreadyLaunched();
    error NotFull();
    error AlreadyPassenger();
    error InvalidAmount();
    error InsufficientFee();
    error CCIPTransferFailed();
    error UnauthorizedSender();
    // UnauthorizedSourceChain, AlreadyReceived, NotReceived, AlreadyDistributed are for receiver contract
    // error UnauthorizedSourceChain();
    // error AlreadyReceived();
    // error NotReceived();
    // error AlreadyDistributed();
    error TokenNotSupported();
    error InvalidTokensAndAmounts();
    error InsufficientNativeBalance();

    constructor(
        address _creator,
        address[] memory _initialTokens,
        uint256[] memory _initialAmounts,
        uint64 _destinationChainSelector,
        uint8 _capacity,
        address _router,
        address _destinationShipReceiver // NEW: Pass the address of the receiver contract on destination
    ) payable OwnerIsCreator() {
        // Removed CCIPReceiver(_router) here
        require(
            _initialTokens.length == _initialAmounts.length,
            "Arrays length mismatch"
        );
        require(_initialTokens.length > 0, "At least one token required");
        require(
            _destinationShipReceiver != address(0),
            "Invalid destinationShipReceiver address"
        );

        CREATOR = _creator;
        DESTINATION_CHAIN_SELECTOR = _destinationChainSelector;
        CAPACITY = _capacity;
        CREATED_AT = block.timestamp;

        I_ROUTER = IRouterClient(_router);
        DESTINATION_SHIP_RECEIVER = _destinationShipReceiver; // Store the receiver address

        // Add supported tokens
        for (uint256 i = 0; i < _initialTokens.length; i++) {
            if (!isTokenSupported[_initialTokens[i]]) {
                supportedTokens.push(_initialTokens[i]);
                isTokenSupported[_initialTokens[i]] = true;
                emit TokenAdded(_initialTokens[i]);
            }
            totalTokenAmounts[_initialTokens[i]] += _initialAmounts[i];
            passengerTokenAmounts[_creator][
                _initialTokens[i]
            ] = _initialAmounts[i];
        }

        // Add creator as first passenger
        passengers.push(_creator);
        passengerIndex[_creator] = 0;
        isPassenger[_creator] = true;
        currentPassengers = 1;

        // Collect fees from msg.value
        collectedFees = msg.value;

        emit PassengerBoarded(_creator, _initialTokens, _initialAmounts, 1);
    }

    function checkUpkeep(
        bytes calldata checkData
    ) external override returns (bool upkeepNeeded, bytes memory performData) {}

    function performUpkeep(bytes calldata performData) external override {}
}