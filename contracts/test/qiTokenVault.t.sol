// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/qiTokenVault.sol";
import "./TestcToken.sol";

contract TestqiTokenVault is DSTest {

    TestcToken public qiToken;
    qiTokenVault public vault;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ADMIN_FEE = 2000;
    uint256 public CALLER_FEE = 100;
    uint256 public MAX_REINVEST_STALE = 1 days;
    uint256 public MAX_INT = 2**256 - 1;
    uint256 public MINT_AMT = 100 * 1e8; // 100 qiToken

    address public WAVAX = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    address public FEE_RECIPIENT = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address public USER = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;

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
        qiToken.mint(address(this), MINT_AMT);
        qiToken.mint(USER, MINT_AMT);
        qiToken.approve(address(vault), MAX_INT);
        qiToken.setExchangeRate(1000000000000000000); // 1 qiToken = 1 underlying token

        vm.startPrank(USER);
        qiToken.approve(address(vault), MAX_INT);
        vm.stopPrank();

        vault.setFeeRecipient(FEE_RECIPIENT);
    }

    function testDeposit() public {
        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qiToken.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - vault.FIRST_DONATION());
    }

    function testDepositFuzz(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 101);

        vault.deposit(address(this), amt * 1e8);
        assertTrue(qiToken.balanceOf(address(vault)) == amt * 1e8);
        assertTrue(vault.balanceOf(address(this)) == amt * 1e18 - vault.FIRST_DONATION());
    }

    function testDepositAndRedeem() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        uint256 preBalanceToken = qiToken.balanceOf(address(this));
        uint256 preBalanceVault = vault.balanceOf(address(this));
        vault.redeem(address(this), preBalanceVault);
        uint256 postBalanceToken = qiToken.balanceOf(address(this));
        uint256 postBalanceVault = vault.balanceOf(address(this));
        assertTrue(postBalanceVault == 0);
        assertTrue(postBalanceToken == preBalanceToken + ((MINT_AMT * 1e10 - vault.FIRST_DONATION()) / 1e10));
    }

    function testDepositAndRedeemFuzz(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 101);

        vault.deposit(address(this), amt * 1e8);
        assertTrue(qiToken.balanceOf(address(vault)) == amt * 1e8);
        assertTrue(vault.balanceOf(address(this)) == amt * 1e18 - vault.FIRST_DONATION());

        uint256 preBalanceToken = qiToken.balanceOf(address(this));
        uint256 preBalanceVault = vault.balanceOf(address(this));
        vault.redeem(address(this), preBalanceVault);
        uint256 postBalanceToken = qiToken.balanceOf(address(this));
        uint256 postBalanceVault = vault.balanceOf(address(this));
        assertTrue(postBalanceVault == 0);
        assertTrue(postBalanceToken == preBalanceToken + ((amt * 1e18 - vault.FIRST_DONATION()) / 1e10));
    }

    function testDepositAndCompound() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qiToken.setExchangeRate(1010000000000000000); // 1 qiToken = 1.01 underlying token

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
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

        uint256 qiTokenBalanceOfUserPost = qiToken.balanceOf(USER);
        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 qiTokenUnderlyingBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;

        assertTrue(qiTokenUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qiTokenBalanceOfVaultPost == qiTokenBalanceOfVaultPre + (MINT_AMT / 10) - totalFeeInUnderlying + 1);
        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfUserPost + (MINT_AMT / 10) - qiTokenBalanceOfUserPre == callerFeeAmt);
    }

    function testDepositAndCompoundFuzz(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 6);

        uint256 NEW_MIN_AMT = 1000 * 1e8 * amt;
        qiToken.mint(address(this), NEW_MIN_AMT);

        vault.deposit(address(this), NEW_MIN_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == NEW_MIN_AMT);
        assertTrue(vault.balanceOf(address(this)) == NEW_MIN_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qiToken.setExchangeRate(1010000000000000000); // 1 qiToken = 1.01 underlying token

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
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

        uint256 qiTokenBalanceOfUserPost = qiToken.balanceOf(USER);
        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 qiTokenUnderlyingBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;

        assertTrue(qiTokenUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qiTokenBalanceOfVaultPost == qiTokenBalanceOfVaultPre + (MINT_AMT / 10) - totalFeeInUnderlying + 1);
        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfUserPost + (MINT_AMT / 10) - qiTokenBalanceOfUserPre == callerFeeAmt);
    }

    function testRedeemAndCompound() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 5);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qiToken.setExchangeRate(1010000000000000000); // 1 qiToken = 1.01 underlying token

        vm.startPrank(USER);
        uint256 vaultBalance = vault.balanceOf(USER);
        vault.redeem(vaultBalance / 2);
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

        uint256 qiTokenBalanceOfUserPre = 90 * 1e8;
        uint256 qiTokenBalanceOfUserPost = qiToken.balanceOf(USER);
        uint256 qiTokenReturnedToUser = vaultTokenBalanceOfUserPre * vault.underlyingPerReceipt() / 1e18;
        uint256 qiTokenBalanceOfVaultPre = 110 * 1e8;
        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 qiTokenUnderlyingBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;
        uint256 qiTokenUnderlyingBalanceOfUser = qiToken.exchangeRate() * qiTokenBalanceOfUserPost / 1e18;

        assertTrue(qiTokenUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qiTokenUnderlyingBalanceOfUser >= MINT_AMT);
        assertTrue(qiTokenBalanceOfVaultPost == qiTokenBalanceOfVaultPre - qiTokenReturnedToUser - totalFeeInUnderlying + 1);
        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfUserPre + qiTokenReturnedToUser + callerFeeAmt == qiTokenBalanceOfUserPost);
    }

    function testSecondHalfOfMinStatement() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qiToken.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 23 hours);
        qiToken.setExchangeRate(1019166666667000000); // 1 qiToken = 1.019166666667 underlying token
        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
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

        uint256 qiTokenBalanceOfVaultPost = qiToken.balanceOf(address(vault));
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 qiTokenBalanceOfUser = vault.balanceOf(USER) * vault.underlyingPerReceipt() / 1e18;
        uint256 qiTokenUnderlyingBalanceOfUser = qiTokenBalanceOfUser * qiToken.exchangeRateCurrent() / 1e8;

        assertTrue(qiToken.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qiTokenBalanceOfVaultPost + totalFeeInUnderlying - 1 == qiTokenBalanceOfVaultPre);
        assertTrue(qiTokenUnderlyingBalanceOfUser >= 10 * 1e18);
    }
}
