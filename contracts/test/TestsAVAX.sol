// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./TestERC20.sol";

contract TestsAVAX is TestERC20 {

    uint public exchangeRate;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) TestERC20(_name, _symbol, _decimals) public {}

    function setExchangeRate(uint _exchangeRate) public {
        exchangeRate = _exchangeRate;
    }

    function getExchangeRate() public view returns (uint) {
        return exchangeRate;
    }

    function getPooledAvaxByShares(uint shareAmount) public view returns (uint) {
        return shareAmount * getExchangeRate() / 1e18;
    }
}
