// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./TestERC20.sol";

contract TestRewardController is TestERC20 {

    uint256 public rewardAmt;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) TestERC20(_name, _symbol, _decimals) public {}

    function setRewardAmt(uint256 _newRewardAmt) public {
        rewardAmt = _newRewardAmt;
    }

    function claimReward(uint8 rewardType, address payable holder) public {
        if(rewardType == 1) {
            mint(holder, rewardAmt);
        }
    }

    function burn(address acount, uint256 amt) public {
        _burn(acount, amt);
    }
}
