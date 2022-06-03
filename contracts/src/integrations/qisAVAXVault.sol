// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {sAVAX} from "src/interfaces/sAVAX.sol";
import {IcToken} from "src/interfaces/cToken.sol";

contract qisAVAXVault is Vault {

    IcToken public qisAVAX;
    address public sAVAXAddr;
    uint256 public lastqisAVAXUnderlyingBalance;
    uint256 public underlyingBalanceAtLastCompound;

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _sAVAX
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
        sAVAXAddr = _sAVAX;
        qisAVAX = IcToken(address(underlying));
    }

    function _getValueOfUnderlyingPre() internal override returns (uint256) {
        return underlyingBalanceAtLastCompound;
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
}
