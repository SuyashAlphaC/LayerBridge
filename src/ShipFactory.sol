//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ship} from "./Ship.sol";

contract ShipFactory is OwnerIsCreator , ReentrancyGuard {
    address private immutable ROUTER;
    
    // Factory state
    // Counters.Counter private shipCounter;
    uint256 private immutable i_gasLimit = 3_000_000;
    uint256 private shipCounter;
    
    // Fee structure (in native tokens)
    uint256 public constant TOKEN_CREATION_FEE = 0.0005 ether; // Per additional token
    mapping(uint8 => uint256) public capacityFees;
    // Ship tracking
    mapping(uint256 => address) public ships;
    mapping(address => uint256[]) public userShips;
    
    // Events
    event ShipCreated(
        uint256 indexed shipId,
        address indexed creator,
        address indexed shipAddress,
        address[] tokens,
        uint8 capacity,
        uint64 destinationChainSelector,
        uint256 feePaid
    );
    
    // Errors
    error InvalidCapacity();
    error InvalidAmount();
    error InsufficientFee();
    error TokenTransferFailed();
    error InvalidTokensAndAmounts();
    
    constructor(address _router) {
        ROUTER = _router;
        shipCounter = 0;
         // Initialize capacity fees (in wei)
        capacityFees[1] = 0.002 ether;   // 1 passenger
        capacityFees[2] = 0.003 ether;   // 2 passengers
        capacityFees[5] = 0.006 ether;   // 5 passengers
        capacityFees[10] = 0.01 ether;   // 10 passengers
    }
     
    function createShip(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        uint64 _destinationChainSelector,
        uint8 _capacity,
        address _destinationShipReceiver
    ) external payable nonReentrant returns (address shipAddress) {
        // Validation
        if (_capacity != 1 && _capacity != 2 && _capacity != 5 && _capacity != 10) {
            revert InvalidCapacity();
        }
        if (_tokens.length != _amounts.length || _tokens.length == 0) {
            revert InvalidTokensAndAmounts();
        }
        
        // Calculate required fee
        uint256 requiredFee = capacityFees[_capacity];
        if (_tokens.length > 1) {
            requiredFee += TOKEN_CREATION_FEE * (_tokens.length - 1);
        }
        
        if (msg.value < requiredFee) revert InsufficientFee();
        
        // Validate amounts and transfer tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_amounts[i] == 0) revert InvalidAmount();
            if (!IERC20(_tokens[i]).transferFrom(msg.sender, address(this), _amounts[i])) {
                revert TokenTransferFailed();
            }
            
        }
        
        // Calculate fee to pass to ship (for CCIP)
        uint256 feeForShip = msg.value - (msg.value / 10); // Keep 10% as factory fee
        
        // Deploy new ship contract
        Ship newShip = new Ship{value: feeForShip}(
            msg.sender,
            _tokens,
            _amounts,
            _destinationChainSelector,
            _capacity,
            ROUTER,
            _destinationShipReceiver
        );
        
        shipAddress = address(newShip);
        
        // Transfer tokens to the new ship
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).transfer(shipAddress, _amounts[i]);
        }
        
        // Record ship
        shipCounter ++ ;
        uint256 shipId = shipCounter;
        ships[shipId] = shipAddress;
        userShips[msg.sender].push(shipId);
        
        emit ShipCreated(
            shipId,
            msg.sender,
            shipAddress,
            _tokens,
            _capacity,
            _destinationChainSelector,
            msg.value
        );
        
        return shipAddress;
    }
    
    /**
     *   * @dev Calculate required fee for ship creation
     */

     function calculateCreationFee(uint8 _capacity, uint256 _tokenCount) 
        external 
        view 
        returns (uint256) 
    {
        uint256 baseFee = capacityFees[_capacity];
        if (_tokenCount > 1) {
            baseFee += TOKEN_CREATION_FEE * (_tokenCount - 1);
        }
        return baseFee;
    }

    function getShip() external {}

    function getUserShips() external{}

    function getTotalShips() external {}

    function updateCapacityFee(uint8 _capacity, uint256 _fees) external {}

    function withdrawExcessFee() external {}

    function getCapacityFee(uint8 _capacity) external {}

    receive() external payable{}
}