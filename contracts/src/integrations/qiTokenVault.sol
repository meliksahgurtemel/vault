// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IcToken} from "src/interfaces/cToken.sol";
import {Math} from "openzeppelin/contracts/utils/math/Math.sol";

contract qisAVAXVault is Vault {

    IcToken public qisAVAX;
    uint256 public lastqisAVAXUnderlyingBalance;
    uint256 public underlyingBalanceAtLastCompound;

    function _initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX
    ) public {
        initialize(
            _underlying,
            _name,
            _symbol,
            _adminFee,
            _callerFee,
            _maxReinvestStale,
            _WAVAX
        );
        qisAVAX = IcToken(address(underlying));
    }

    function _getValueOfUnderlyingPre() internal override returns (uint256) {
        return lastqisAVAXUnderlyingBalance;
    }

    function _getValueOfUnderlyingPost() internal override returns (uint256) {
        return qisAVAX.balanceOfUnderlying(address(this));
    }

    function totalHoldings() public override returns (uint256) {
        return qisAVAX.balanceOfUnderlying(address(this));
    }

    function _triggerDepositAction(uint256 amt) internal override {
        underlyingBalanceAtLastCompound += (amt * qisAVAX.exchangeRateCurrent()) / 1e8;
        lastqisAVAXUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(this));
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        underlyingBalanceAtLastCompound -= (amtToReturn * qisAVAX.exchangeRateCurrent()) / 1e8;
        lastqisAVAXUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(this)) - ((amtToReturn * qisAVAX.exchangeRateCurrent()) / 1e8);
    }

    function _doSomethingPostCompound() internal override {
        underlyingBalanceAtLastCompound = qisAVAX.balanceOfUnderlying(address(this));
        lastqisAVAXUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(this));
    }

    function _compound() internal override returns (uint256) {
        address _underlyingAddress = address(underlying);
        lastReinvestTime = block.timestamp;
        uint256 lastUnderlyingBalance = _getValueOfUnderlyingPre();
        _pullRewards();
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] != address(0)) {
                if (rewardTokens[i] == _underlyingAddress) continue;
                if (rewardTokens[i] == address(1)) {
                    // Token is native currency
                    // Deposit for WAVAX
                    uint256 nativeBalance = address(this).balance;
                    if (nativeBalance > MIN_SWAP) {
                        WAVAX.deposit{value: nativeBalance}();
                        swap(
                            address(WAVAX),
                            _underlyingAddress,
                            nativeBalance,
                            0
                        );
                    }
                } else {
                    uint256 rewardBalance = IERC20(rewardTokens[i]).balanceOf(
                        address(this)
                    );
                    if (rewardBalance * (10 ** (18 - IERC20(rewardTokens[i]).decimals())) > MIN_SWAP ) {
                        swap(
                            rewardTokens[i],
                            _underlyingAddress,
                            rewardBalance,
                            0
                        );
                    }
                }
            }
        }
        uint256 currentUnderlyingBalance = _getValueOfUnderlyingPost();
        uint256 totalFeeInValue = Math.min((currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (adminFee + callerFee) / 10000, currentUnderlyingBalance - lastUnderlyingBalance);
        if (totalFeeInValue > 0) {
            // convert the profit in value to profit in underlying
            uint256 totalFeeInUnderlying = totalFeeInValue * underlying.balanceOf(address(this)) / currentUnderlyingBalance;
            uint256 adminAmt = totalFeeInUnderlying * adminFee / (adminFee + callerFee);
            uint256 callerAmt = totalFeeInUnderlying * callerFee / (adminFee + callerFee);

            SafeTransferLib.safeTransfer(underlying, feeRecipient, adminAmt);
            SafeTransferLib.safeTransfer(underlying, msg.sender, callerAmt);
            emit Reinvested(
                msg.sender,
                lastUnderlyingBalance,
                currentUnderlyingBalance
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
