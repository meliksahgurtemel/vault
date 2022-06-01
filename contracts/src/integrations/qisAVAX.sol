// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IcToken} from "src/interfaces/cToken.sol";

contract qisAVAXVault is Vault {

    IcToken public qisAVAX;
    uint256 public lastqisAVAXUnderlyingBalance;

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

    function _triggerDepositAction(uint256 amtToReturn) internal override {
        lastqisAVAXUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(this));
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        lastqisAVAXUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(this)) - ((amtToReturn * qisAVAX.exchangeRateCurrent()) / 1e18);
    }

    function _doSomethingPostCompound() internal override {
        lastqisAVAXUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(this));
    }
}
