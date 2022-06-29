// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/qiTokenVault.sol";
import "./TestcToken.sol";
import "./MockqiTokenVault.sol";

contract TestqiTokenVault is DSTest {

    TestcToken public qiToken;
    qiTokenVault public vault;
    MockqiTokenVault public vault2;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ADMIN_FEE = 2000;
    uint256 public CALLER_FEE = 100;
    uint256 public MAX_REINVEST_STALE = 1 days;
    uint256 public MAX_INT = 2**256 - 1;
    uint256 public MINT_AMT = 100 * 1e8; // 100 qiToken

    address public WAVAX = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    address public FEE_RECIPIENT = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address public USER = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    address public USER2 = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function setUp() public {
        qiToken = new TestcToken(
            "Benqi Token",
            "qiToken",
            8
        );
        vault = new qiTokenVault();
        vault._initialize(
            address(qiToken),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            WAVAX
        );
        vault2 = new MockqiTokenVault();
        vault2._initialize(
            address(qiToken),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            WAVAX
        );
        qiToken.mint(address(this), MINT_AMT * 2);
        qiToken.mint(USER, MINT_AMT);
        qiToken.mint(USER2, MINT_AMT);
        qiToken.approve(address(vault), MAX_INT);
        qiToken.approve(address(vault2), MAX_INT);
        qiToken.setExchangeRate(1000000000000000000); // 1 qiToken = 1 underlying token

        vm.startPrank(USER);
        qiToken.approve(address(vault), MAX_INT);
        vm.stopPrank();

        vm.startPrank(USER2);
        qiToken.approve(address(vault2), MAX_INT);
        vm.stopPrank();

        vault.setFeeRecipient(FEE_RECIPIENT);
        vault2.setFeeRecipient(FEE_RECIPIENT);
    }

    function testDepositAndCompound() public {
        vault.deposit(address(this), MINT_AMT);
        vault2.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qiToken.setExchangeRate(1010000000000000000); // 1 qiToken = 1.01 underlying token

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        vm.startPrank(USER2);
        vault2.deposit(USER2, MINT_AMT / 10);
        vm.stopPrank();

        qiToken.setExchangeRate(1020000000000000000); // 1 qiToken = 1.02 underlying token
        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale

        uint256 qiTokenBalanceOfUserPre = qiToken.balanceOf(USER);
        uint256 qiTokenBalanceOfVaultPre = qiToken.balanceOf(address(vault));
        uint256 currentUnderlyingBalance = qiToken.balanceOfUnderlying(address(vault));
        uint256 lastUnderlyingBalance = vault.lastqiTokenUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();

        uint256 totalFee = (currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000;
        uint256 totalFeeInUnderlying = totalFee * qiToken.balanceOf(address(vault)) / currentUnderlyingBalance;
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        vm.startPrank(USER2);
        vault2.deposit(USER2, MINT_AMT / 10);
        vm.stopPrank();

        uint256 qiTokenBalanceOfUserPost = qiToken.balanceOf(USER);
        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 qiTokenUnderlyingBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;
        uint256 vault2AdminFeeAmt = (vault2.balanceOf(FEE_RECIPIENT) * vault2.underlyingPerReceipt()) / 1e18;

        assertTrue(qiTokenUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qiTokenBalanceOfVaultPost == qiTokenBalanceOfVaultPre + (MINT_AMT / 10) - totalFeeInUnderlying + 1);
        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfUserPost + (MINT_AMT / 10) - qiTokenBalanceOfUserPre == callerFeeAmt);

        console.log(adminFeeAmt);
        console.log(vault2AdminFeeAmt);
        console.log(adminFeeAmt - vault2AdminFeeAmt);
    }

    function testRedeemAndCompound() public {
        vault.deposit(address(this), MINT_AMT);
        vault2.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 5);
        vm.stopPrank();

        vm.startPrank(USER2);
        vault2.deposit(USER2, MINT_AMT / 5);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qiToken.setExchangeRate(1010000000000000000); // 1 qiToken = 1.01 underlying token

        vm.startPrank(USER);
        uint256 vaultBalance = vault.balanceOf(USER);
        vault.redeem(vaultBalance / 2);
        vm.stopPrank();

        vm.startPrank(USER2);
        uint256 vault2Balance = vault2.balanceOf(USER2);
        vault2.redeem(vault2Balance / 2);
        vm.stopPrank();

        qiToken.setExchangeRate(1020000000000000000); // 1 qiToken = 1.02 underlying token
        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale

        uint256 currentUnderlyingBalance = qiToken.balanceOfUnderlying(address(vault));
        uint256 lastUnderlyingBalance = vault.lastqiTokenUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();

        uint256 totalFee = (currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000;
        uint256 totalFeeInUnderlying = totalFee * qiToken.balanceOf(address(vault)) / currentUnderlyingBalance;
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 vaultTokenBalanceOfUserPre = vault.balanceOf(USER);

        vm.startPrank(USER);
        vault.redeem(vault.balanceOf(USER));
        vm.stopPrank();

        vm.startPrank(USER2);
        vault2.redeem(vault.balanceOf(USER2));
        vm.stopPrank();

        uint256 qiTokenBalanceOfUserPre = 90 * 1e8;
        uint256 qiTokenBalanceOfUserPost = qiToken.balanceOf(USER);
        uint256 qiTokenReturnedToUser = vaultTokenBalanceOfUserPre * vault.underlyingPerReceipt() / 1e18;
        uint256 qiTokenBalanceOfVaultPre = 110 * 1e8;
        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 qiTokenBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;
        uint256 qiTokenUnderlyingBalance = qiTokenBalance * qiToken.exchangeRate() / 1e18;
        uint256 qiTokenUnderlyingBalanceOfUser = qiTokenBalanceOfUserPost * qiToken.exchangeRate() / 1e18;
        uint256 vault2AdminFeeAmt = (vault2.balanceOf(FEE_RECIPIENT) * vault2.underlyingPerReceipt()) / 1e18;

        assertTrue(qiTokenUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qiTokenUnderlyingBalanceOfUser >= MINT_AMT);
        assertTrue(qiTokenBalanceOfVaultPost == qiTokenBalanceOfVaultPre - qiTokenReturnedToUser - totalFeeInUnderlying + 1);
        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfUserPre + qiTokenReturnedToUser + callerFeeAmt == qiTokenBalanceOfUserPost);

        console.log(adminFeeAmt);
        console.log(vault2AdminFeeAmt);
        console.log(adminFeeAmt - vault2AdminFeeAmt);
    }

    function testSecondHalfOfMinStatement() public {
        vault.deposit(address(this), MINT_AMT);
        vault2.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 23 hours);
        qiToken.setExchangeRate(1019166666667000000); // 1 qiToken = 1.019166666667 underlying token

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        vm.startPrank(USER2);
        vault2.deposit(USER2, MINT_AMT / 10);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale
        qiToken.setExchangeRate(1020000000000000000); // 1 qiToken = 1.02 underlying token

        uint256 currentUnderlyingBalance = qiToken.balanceOfUnderlying(address(vault));
        uint256 lastUnderlyingBalance = vault.lastqiTokenUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();
        uint256 qiTokenBalanceOfVaultPre = qiToken.balanceOf(address(vault));
        uint256 totalFee = Math.min((currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000, currentUnderlyingBalance - lastUnderlyingBalance);
        uint256 totalFeeInUnderlying = totalFee * qiToken.balanceOf(address(vault)) / currentUnderlyingBalance;
        vault.compound();
        vault2.compound();

        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 qiTokenBalanceOfUser = vault.balanceOf(USER) * vault.underlyingPerReceipt() / 1e18;
        uint256 qiTokenUnderlyingBalanceOfUser = qiTokenBalanceOfUser * qiToken.exchangeRateCurrent() / 1e8;
        uint256 vault2AdminFeeAmt = (vault2.balanceOf(FEE_RECIPIENT) * vault2.underlyingPerReceipt()) / 1e18;

        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfVaultPost + totalFeeInUnderlying - 1 == qiTokenBalanceOfVaultPre);
        assertTrue(qiTokenUnderlyingBalanceOfUser >= 10 * 1e18);

        console.log(adminFeeAmt);
        console.log(vault2AdminFeeAmt);
        console.log(adminFeeAmt - vault2AdminFeeAmt);
    }
}
