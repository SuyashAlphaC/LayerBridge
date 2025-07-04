//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

contract ShipFactory { 
    function createShip() external {}

    function calculateCreationFee() external {}

    function getShip() external {}

    function getUserShips() external{}

    function getTotalShips() external {}

    function updateCapacityFee(uint8 _capacity, uint256 _fees) external {}

    function withdrawExcessFee() external {}

    function getCapacityFee(uint8 _capacity) external {}

    receive() external payable{}
}