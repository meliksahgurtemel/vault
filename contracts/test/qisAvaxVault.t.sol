// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/qisAvaxVault.sol";
import "./TestcToken.sol";
import "./TestsAVAX.sol";

contract TestqisAVAXVault is DSTest {

    TestsAVAX public sAvax;
    TestcToken public qisAVAX;
    qisAVAXVault public vault;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ADMIN_FEE = 2000;
    uint256 public CALLER_FEE = 100;
    uint256 public MAX_REINVEST_STALE = 1 days;
    uint256 public MAX_INT = 2**256 - 1;
    uint256 public MINT_AMT = 100 * 1e8; // 100 qisAVAX

    address public WAVAX = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    address public FEE_RECIPIENT = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address public USER = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;

    function setUp() public {
        qisAVAX = new TestcToken(
            "Benqi Token",
            "qisAVAX",
            8
        );
        sAvax = new TestsAVAX(
            "Staked AVAX",
            "sAVAX",
            18
        );
        vault = new qisAVAXVault();
        vault._initialize(
            address(qisAVAX),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            WAVAX,
            address(sAvax)
        );
        qisAVAX.mint(address(this), MINT_AMT);
        qisAVAX.mint(USER, MINT_AMT);
        qisAVAX.approve(address(vault), MAX_INT);
        qisAVAX.setExchangeRate(1000000000000000000); // 1 qisAVAX = 1 sAVAX
        sAvax.setExchangeRate(1000000000000000000); // 1 sAVAX = 1 AVAX

        vm.startPrank(USER);
        qisAVAX.approve(address(vault), MAX_INT);
        vm.stopPrank();

        vault.setFeeRecipient(FEE_RECIPIENT);
    }

    function testDeposit() public {
        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qisAVAX.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - vault.FIRST_DONATION());
    }

    function testDepositFuzz(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 101);

        vault.deposit(address(this), amt * 1e8);
        assertTrue(qisAVAX.balanceOf(address(vault)) == amt * 1e8);
        assertTrue(vault.balanceOf(address(this)) == amt * 1e18 - vault.FIRST_DONATION());
    }

    function testDepositAndRedeem() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qisAVAX.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        uint256 preBalanceToken = qisAVAX.balanceOf(address(this));
        uint256 preBalanceVault = vault.balanceOf(address(this));
        vault.redeem(address(this), preBalanceVault);
        uint256 postBalanceToken = qisAVAX.balanceOf(address(this));
        uint256 postBalanceVault = vault.balanceOf(address(this));
        assertTrue(postBalanceVault == 0);
        assertTrue(postBalanceToken == preBalanceToken + ((MINT_AMT * 1e10 - vault.FIRST_DONATION()) / 1e10));
    }

    function testDepositAndRedeemFuzz(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 101);

        vault.deposit(address(this), amt * 1e8);
        assertTrue(qisAVAX.balanceOf(address(vault)) == amt * 1e8);
        assertTrue(vault.balanceOf(address(this)) == amt * 1e18 - vault.FIRST_DONATION());

        uint256 preBalanceToken = qisAVAX.balanceOf(address(this));
        uint256 preBalanceVault = vault.balanceOf(address(this));
        vault.redeem(address(this), preBalanceVault);
        uint256 postBalanceToken = qisAVAX.balanceOf(address(this));
        uint256 postBalanceVault = vault.balanceOf(address(this));
        assertTrue(postBalanceVault == 0);
        assertTrue(postBalanceToken == preBalanceToken + ((amt * 1e18 - vault.FIRST_DONATION()) / 1e10));
    }

    function testDepositAndCompound() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qisAVAX.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qisAVAX.setExchangeRate(1010000000000000000); // 1 qisAVAX = 1.01 sAVAX
        sAvax.setExchangeRate(1015000000000000000); // 1 sAVAX = 1.015 AVAX

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        qisAVAX.setExchangeRate(1020000000000000000); // 1 qisAVAX = 1.02 sAVAX
        sAvax.setExchangeRate(1030000000000000000); // 1 sAVAX = 1.03 AVAX
        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale

        uint256 qisAVAXBalanceOfUserPre = qisAVAX.balanceOf(USER);
        uint256 qisAVAXBalanceOfVaultPre = qisAVAX.balanceOf(address(vault));
        uint256 currentqisAvaxBalance = qisAVAX.balanceOfUnderlying(address(vault));
        uint256 currentUnderlyingBalance = sAvax.getPooledAvaxByShares(currentqisAvaxBalance);
        uint256 lastUnderlyingBalance = vault.lastqisAVAXUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();

        uint256 totalFee = (currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000;
        uint256 totalFeeInUnderlying = totalFee * qisAVAX.balanceOf(address(vault)) / currentUnderlyingBalance;
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        uint256 qisAVAXBalanceOfUserPost = qisAVAX.balanceOf(USER);
        uint256 qisAVAXBalanceOfVaultPost = qisAVAX.balanceOf(address(vault));
        uint256 qisAVAXUnderlyingBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;

        assertTrue(qisAVAXUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qisAVAXBalanceOfVaultPost == qisAVAXBalanceOfVaultPre + (MINT_AMT / 10) - totalFeeInUnderlying + 1);
        assertTrue(qisAVAX.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qisAVAXBalanceOfUserPost + (MINT_AMT / 10) - qisAVAXBalanceOfUserPre == callerFeeAmt);
    }

    function testDepositAndCompoundFuzz(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 6);

        uint256 NEW_MIN_AMT = 1000 * 1e8 * amt;
        qisAVAX.mint(address(this), NEW_MIN_AMT);

        vault.deposit(address(this), NEW_MIN_AMT);
        assertTrue(qisAVAX.balanceOf(address(vault)) == NEW_MIN_AMT);
        assertTrue(vault.balanceOf(address(this)) == NEW_MIN_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qisAVAX.setExchangeRate(1010000000000000000); // 1 qisAVAX = 1.01 sAVAX
        sAvax.setExchangeRate(1015000000000000000); // 1 sAVAX = 1.015 AVAX

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        qisAVAX.setExchangeRate(1020000000000000000); // 1 qisAVAX = 1.02 sAVAX
        sAvax.setExchangeRate(1030000000000000000); // 1 sAVAX = 1.03 AVAX
        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale

        uint256 qisAVAXBalanceOfUserPre = qisAVAX.balanceOf(USER);
        uint256 qisAVAXBalanceOfVaultPre = qisAVAX.balanceOf(address(vault));
        uint256 currentqisAvaxBalance = qisAVAX.balanceOfUnderlying(address(vault));
        uint256 currentUnderlyingBalance = sAvax.getPooledAvaxByShares(currentqisAvaxBalance);
        uint256 lastUnderlyingBalance = vault.lastqisAVAXUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();

        uint256 totalFee = (currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000;
        uint256 totalFeeInUnderlying = totalFee * qisAVAX.balanceOf(address(vault)) / currentUnderlyingBalance;
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        uint256 qisAVAXBalanceOfUserPost = qisAVAX.balanceOf(USER);
        uint256 qisAVAXBalanceOfVaultPost = qisAVAX.balanceOf(address(vault));
        uint256 qisAVAXUnderlyingBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;
        uint256 qisAVAXBalanceOfVaultAfterCompound = qisAVAXBalanceOfVaultPre + (MINT_AMT / 10) - totalFeeInUnderlying;

        assertTrue(qisAVAXUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qisAVAXBalanceOfVaultPost == qisAVAXBalanceOfVaultAfterCompound || qisAVAXBalanceOfVaultPost == qisAVAXBalanceOfVaultAfterCompound + 1);
        assertTrue(qisAVAX.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qisAVAXBalanceOfUserPost + (MINT_AMT / 10) - qisAVAXBalanceOfUserPre == callerFeeAmt);
    }

    function testRedeemAndCompound() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qisAVAX.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 5);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 12 hours); // half of the stale
        qisAVAX.setExchangeRate(1010000000000000000); // 1 qisAVAX = 1.01 sAVAX
        sAvax.setExchangeRate(1015000000000000000); // 1 sAVAX = 1.015 AVAX

        vm.startPrank(USER);
        uint256 vaultBalance = vault.balanceOf(USER);
        vault.redeem(vaultBalance / 2);
        vm.stopPrank();

        qisAVAX.setExchangeRate(1020000000000000000); // 1 qisAVAX = 1.02 sAVAX
        sAvax.setExchangeRate(1030000000000000000); // 1 sAVAX = 1.03 AVAX
        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale

        uint256 currentqisAvaxBalance = qisAVAX.balanceOfUnderlying(address(vault));
        uint256 currentUnderlyingBalance = sAvax.getPooledAvaxByShares(currentqisAvaxBalance);
        uint256 lastUnderlyingBalance = vault.lastqisAVAXUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();

        uint256 totalFee = (currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000;
        uint256 totalFeeInUnderlying = totalFee * qisAVAX.balanceOf(address(vault)) / currentUnderlyingBalance;
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 vaultTokenBalanceOfUserPre = vault.balanceOf(USER);

        vm.startPrank(USER);
        vault.redeem(vault.balanceOf(USER));
        vm.stopPrank();

        uint256 qisAVAXBalanceOfUserPre = 90 * 1e8;
        uint256 qisAVAXBalanceOfUserPost = qisAVAX.balanceOf(USER);
        uint256 qisAVAXReturnedToUser = vaultTokenBalanceOfUserPre * vault.underlyingPerReceipt() / 1e18;
        uint256 qisAVAXBalanceOfVaultPre = 110 * 1e8;
        uint256 qisAVAXBalanceOfVaultPost = qisAVAX.balanceOf(address(vault));
        uint256 qisAVAXBalance = vault.underlyingPerReceipt() * vault.balanceOf(address(this)) / 1e18;
        uint256 sAVAXBalance = qisAVAXBalance * qisAVAX.exchangeRate() / 1e18;
        uint256 qisAVAXUnderlyingBalance = sAvax.getPooledAvaxByShares(sAVAXBalance);
        uint256 qisAVAXUnderlyingBalanceOfUser = qisAVAXBalanceOfUserPost * qisAVAX.exchangeRate() / 1e18;

        assertTrue(qisAVAXUnderlyingBalance >= MINT_AMT - vault.FIRST_DONATION());
        assertTrue(qisAVAXUnderlyingBalanceOfUser >= MINT_AMT);
        assertTrue(qisAVAXBalanceOfVaultPost == qisAVAXBalanceOfVaultPre - qisAVAXReturnedToUser - totalFeeInUnderlying);
        assertTrue(qisAVAX.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qisAVAXBalanceOfUserPre + qisAVAXReturnedToUser + callerFeeAmt == qisAVAXBalanceOfUserPost);
    }

    function testSecondHalfOfMinStatement() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qisAVAX.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 23 hours); // 1h before the stale
        qisAVAX.setExchangeRate(1019166666667000000); // 1 qisAVAX = 1.019166666667 sAVAX
        sAvax.setExchangeRate(1028750000000000000); // 1 sAVAX = 1.02875 AVAX

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 1 + 24 hours); // end of the stale
        qisAVAX.setExchangeRate(1020000000000000000); // 1 qisAVAX = 1.02 sAVAX
        sAvax.setExchangeRate(1030000000000000000); // 1 sAVAX = 1.03 AVAX

        uint256 currentqisAvaxBalance = qisAVAX.balanceOfUnderlying(address(vault));
        uint256 currentUnderlyingBalance = sAvax.getPooledAvaxByShares(currentqisAvaxBalance);
        uint256 lastUnderlyingBalance = vault.lastqisAVAXUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();
        uint256 qisAVAXBalanceOfVaultPre = qisAVAX.balanceOf(address(vault));
        uint256 totalFee = Math.min((currentUnderlyingBalance - underlyingBalanceAtLastCompound) * (ADMIN_FEE + CALLER_FEE) / 10000, currentUnderlyingBalance - lastUnderlyingBalance);
        uint256 totalFeeInUnderlying = totalFee * qisAVAX.balanceOf(address(vault)) / currentUnderlyingBalance;
        vault.compound();

        uint256 qisAVAXBalanceOfVaultPost = qisAVAX.balanceOf(address(vault));
        uint256 adminFeeAmt = totalFeeInUnderlying * ADMIN_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 callerFeeAmt = totalFeeInUnderlying * CALLER_FEE / (ADMIN_FEE + CALLER_FEE);
        uint256 qisAVAXBalanceOfUser = vault.balanceOf(USER) * vault.underlyingPerReceipt() / 1e18;
        uint256 qisAVAXUnderlyingBalanceOfUser = qisAVAXBalanceOfUser * qisAVAX.exchangeRateCurrent() / 1e8;

        assertTrue(qisAVAX.balanceOf(FEE_RECIPIENT) == adminFeeAmt);
        assertTrue(qisAVAXBalanceOfVaultPost + totalFeeInUnderlying - 1 == qisAVAXBalanceOfVaultPre);
        assertTrue(qisAVAXUnderlyingBalanceOfUser >= 10 * 1e18);
    }
}
