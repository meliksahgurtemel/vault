// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {ICompRewardController} from "src/interfaces/ICompRewardController.sol";
import {IcToken} from "src/interfaces/cToken.sol";

contract TestCompVault is Vault {

    ICompRewardController public rewardController;
    IcToken public cToken;

    uint256 public lastCTokenUnderlyingBalance;

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _rewardController
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        rewardController = ICompRewardController(_rewardController);
        cToken = IcToken(address(underlying));
    }

    // Reward 1 = WAVAX rewards
    function _pullRewards() internal override {
        rewardController.claimReward(1, payable(address(this)));
    }

    function _getValueOfUnderlyingPre() internal override returns (uint256) {
        return lastCTokenUnderlyingBalance;
    }

    function _getValueOfUnderlyingPost() internal override returns (uint256) {

        return cToken.balanceOfUnderlying(address(this));
    }
    function totalHoldings() public override returns (uint256) {
        return cToken.balanceOfUnderlying(address(this));
    }

    function _triggerDepositAction(uint256 amtToReturn) internal override {
        lastCTokenUnderlyingBalance = cToken.balanceOfUnderlying(address(this));
    }
    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        lastCTokenUnderlyingBalance = cToken.balanceOfUnderlying(address(this)) - ((amtToReturn * cToken.exchangeRateCurrent()) / 1e18);
    }
    function _doSomethingPostCompound() internal override {
        lastCTokenUnderlyingBalance = cToken.balanceOfUnderlying(address(this));
    }

    function _compound() internal override returns (uint256) {
        address _underlyingAddress = address(underlying);
        lastReinvestTime = block.timestamp;
        uint256 preCompoundUnderlyingValue = _getValueOfUnderlyingPre();
        _pullRewards();

        //simulate swap
        uint256 rewardBalance = rewardController.balanceOf(address(this));
        rewardController.burn(address(this), rewardBalance);
        cToken.mint(address(this), (rewardBalance * 50));

        uint256 postCompoundUnderlyingValue = _getValueOfUnderlyingPost();
        uint256 profitInValue = postCompoundUnderlyingValue - preCompoundUnderlyingValue;
        if (profitInValue > 0) {
            // convert the profit in value to profit in underlying
            uint256 profitInUnderlying = profitInValue * underlying.balanceOf(address(this)) / postCompoundUnderlyingValue;
            uint256 adminAmt = (profitInUnderlying * adminFee) / 10000;
            uint256 callerAmt = (profitInUnderlying * callerFee) / 10000;

            SafeTransferLib.safeTransfer(underlying, feeRecipient, adminAmt);
            SafeTransferLib.safeTransfer(underlying, msg.sender, callerAmt);
            emit Reinvested(
                msg.sender,
                preCompoundUnderlyingValue,
                postCompoundUnderlyingValue
            );
            emit AdminFeePaid(feeRecipient, adminAmt);
            emit CallerFeePaid(msg.sender, callerAmt);
            // For tokens which have to deposit their newly minted tokens to deposit them into another contract,
            // call that action. New tokens = current balance of underlying.
            _triggerDepositAction(underlying.balanceOf(address(this)));
        }
        _doSomethingPostCompound();
    }
}
