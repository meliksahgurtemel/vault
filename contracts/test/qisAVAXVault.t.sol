// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/qisAVAXVault.sol";
import "./TestcToken.sol";
import "./TestsAVAX.sol";

contract TestqisAVAXVault is DSTest {

    TestsAVAX public sAVAX;
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
        sAVAX = new TestsAVAX(
            "Staked AVAX",
            "sAVAX",
            18
        );
        vault = new qisAVAXVault();
        vault.initialize(
            address(qisAVAX),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            WAVAX,
            address(sAVAX)
        );
        qisAVAX.mint(address(this), MINT_AMT);
        qisAVAX.mint(USER, MINT_AMT);
        qisAVAX.approve(address(vault), MAX_INT);
        qisAVAX.setExchangeRate(1050000000000000000); // 1 qisAVAX = 1.05 sAVAX ratio
        sAVAX.setExchangeRate(1070000000000000000); // 1 sAVAX = 1.07 AVAX ratio

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

    function testDepositAndCompound(uint amt) public {
        vm.assume(amt > 0);
        vm.assume(amt < 101);

        vault.deposit(address(this), amt * 1e8);
        assertTrue(qisAVAX.balanceOf(address(vault)) == amt * 1e8);
        assertTrue(vault.balanceOf(address(this)) == amt * 1e18 - vault.FIRST_DONATION());

        vm.warp(vault.lastReinvestTime() + 3601); // +1h

        sAVAX.setExchangeRate(1100000000000000000); // set exchange rate to %10
        uint256 preBalanceToken = qisAVAX.balanceOf(FEE_RECIPIENT);
        uint256 preBalanceVault = qisAVAX.balanceOf(address(vault));
        vault.compound();
        uint256 postBalanceToken = qisAVAX.balanceOf(FEE_RECIPIENT);
        uint256 postBalanceVault = qisAVAX.balanceOf(address(vault));
        assertTrue(postBalanceToken > preBalanceToken);
        assertTrue(postBalanceVault < preBalanceVault);
    }
}
