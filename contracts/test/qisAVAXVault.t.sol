// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/qisAVAXVault.sol";
import "./TestcToken.sol";

contract TestqisAVAXVault is DSTest {

    TestcToken public qisAVAX;
    qisAVAXVault public vault;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ADMIN_FEE = 2000;
    uint256 public CALLER_FEE = 100;
    uint256 public MAX_REINVEST_STALE = 1 hours;
    uint256 public MAX_INT = 2**256 - 1;
    uint256 public MINT_AMT = 100 * 1e8; // 100 qisAVAX

    address public WAVAX = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    address public FEE_RECIPIENT = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address public USER = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;

    function setUp() public {
        qisAVAX = new TestcToken(
            "Benqi sAVAX",
            "qisAVAX",
            8
        );
        vault = new qisAVAXVault();
        vault._initialize(
            address(qisAVAX),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            WAVAX
        );
        qisAVAX.mint(address(this), MINT_AMT);
        qisAVAX.mint(USER, MINT_AMT);
        qisAVAX.approve(address(vault), MAX_INT);
        qisAVAX.setExchangeRate(1000000000000000000); // 1 qisAVAX = 1.05 sAVAX ratio

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

    function testCompound() public {
        vault.deposit(address(this), MINT_AMT);
        assertTrue(qisAVAX.balanceOf(address(vault)) == MINT_AMT);
        assertTrue(vault.balanceOf(address(this)) == MINT_AMT * 1e10 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 1800); // half of the stale

        qisAVAX.setExchangeRate(1010000000000000000); // 1 qisAVAX = 1.01 sAVAX

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        qisAVAX.setExchangeRate(1020000000000000000); // 1 qisAVAX = 1.02 sAVAX

        vm.warp(vault.lastReinvestTime() + 3601); // end of the stale

        uint256 qisAVAXBalanceUserPre = qisAVAX.balanceOf(USER);
        uint256 qisAVAXBalanceVaultPre = qisAVAX.balanceOf(address(vault));
        uint256 currentUnderlyingBalance = qisAVAX.balanceOfUnderlying(address(vault));
        uint256 lastUnderlyingBalance = vault.lastqisAVAXUnderlyingBalance();
        uint256 underlyingBalanceAtLastCompound = vault.underlyingBalanceAtLastCompound();

        uint256 profit = (currentUnderlyingBalance - underlyingBalanceAtLastCompound) * ADMIN_FEE / 10000;
        uint256 profitInUnderlying = profit * qisAVAX.balanceOf(address(vault)) / currentUnderlyingBalance;
        uint256 callerFee = (profitInUnderlying * CALLER_FEE) / 10000;

        vm.startPrank(USER);
        vault.deposit(USER, MINT_AMT / 10);
        vm.stopPrank();

        uint256 qisAVAXBalanceUserPost = qisAVAX.balanceOf(USER);
        uint256 qisAVAXBalanceVaultPost = qisAVAX.balanceOf(address(vault));
        assertTrue(qisAVAXBalanceVaultPost == qisAVAXBalanceVaultPre + (MINT_AMT / 10) - profitInUnderlying - callerFee);
        assertTrue(qisAVAX.balanceOf(FEE_RECIPIENT) == profitInUnderlying);
        assertTrue(qisAVAXBalanceUserPost + (MINT_AMT / 10) - qisAVAXBalanceUserPre == callerFee);
    }
}
