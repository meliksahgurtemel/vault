// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./TestERC20.sol";

contract TestcToken is TestERC20 {

    uint public exchangeRate;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) TestERC20(_name, _symbol, _decimals) public {}

    function setExchangeRate(uint _exchangeRate) public {
        exchangeRate = _exchangeRate;
    }

    function exchangeRateCurrent() public returns (uint) {
        return exchangeRate;
    }

    function balanceOfUnderlying(address account) public returns (uint) {
        return balanceOf[account];
    }
}
