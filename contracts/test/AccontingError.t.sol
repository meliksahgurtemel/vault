// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/CompVault.sol";
import "./TestcToken.sol";
import "./TestRewardController.sol";

contract TestAccountingError is DSTest {

    TestcToken public qiUSDC;
    CompVault public vault;
    TestRewardController public rewardController;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ADMIN_FEE = 2000;
    uint256 public CALLER_FEE = 100;
    uint256 public MAX_REINVEST_STALE = 1 hours;
    uint256 public MAX_INT = 2**256 - 1;
    uint256 public MINT_AMT = 100 * 1e8; // 100 qiUSDC

    address public FEE_RECIPIENT = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address public USER = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;

    function setUp() public {
        qiUSDC = new TestcToken(
            "Benqi USDC",
            "qiUSDC",
            8
        );
        rewardController = new TestRewardController(
            "Wrapped AVAX",
            "WAVAX",
            18
        );
        vault = new CompVault();
        vault.initialize(
            address(qiUSDC),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            address(rewardController),
            address(rewardController)
        );
        qiUSDC.mint(address(this), MINT_AMT);
        qiUSDC.mint(USER, MINT_AMT);
        qiUSDC.approve(address(vault), MAX_INT);
        qiUSDC.setExchangeRate(1000000000000000000);

        vault.pushRewardToken(address(rewardController));
        vault.setFeeRecipient(FEE_RECIPIENT);
    }

    function testAccError() public {
        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - 1e8);

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        uint256 preBalance = vault.balanceOf(USER);
        uint256 preQIUSDCBalance = qiUSDC.balanceOf(address(vault));

        vm.startPrank(USER);
        qiUSDC.approve(address(vault), MAX_INT);
        vault.deposit(USER, MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preQIUSDCBalance + 50 * 1e8);
        assertTrue(vault.balanceOf(USER) == preBalance + 50 * 1e18);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 preVaultBalance = qiUSDC.balanceOf(address(vault)) + 50 * 1e8;

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);

        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // Assume WAVAX is 50$ and qiUSDC to USDC ratio is 1. So, it makes 450 qiUSDC.
        // %20 of the qiUSDC goes to the fee recipient (admin).
        uint256 adminFee = 90 * 1e8;
        uint256 callerFee = 450 * 1e8 / 100;
        assertTrue(qiUSDC.balanceOf(FEE_RECIPIENT) == adminFee);
        assertTrue(qiUSDC.balanceOf(address(this)) == callerFee);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preVaultBalance + ((450 * 1e8) - adminFee - callerFee));
    }

    function testAccError2() public {
        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - 1e8);

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        uint256 preBalance = vault.balanceOf(USER);
        uint256 preQIUSDCBalance = qiUSDC.balanceOf(address(vault));

        vm.startPrank(USER);
        qiUSDC.approve(address(vault), MAX_INT);
        vault.deposit(USER, MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preQIUSDCBalance + 50 * 1e8);
        assertTrue(vault.balanceOf(USER) == preBalance + 50 * 1e18);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);

        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // However, it should be (%20 * 60min) + (%20 * 60min) = 12 WAVAX rewards in 1h stale.
        // Assume WAVAX is 50$ and qiUSDC to USDC ratio is 1. So, with the correct accounting it should be 600 qiUSDC.
        // %20 of the qiUSDC goes to the fee recipient.
        assertTrue(qiUSDC.balanceOf(FEE_RECIPIENT) != (120 * 1e8)); // expected to fail because of the accounting error
    }

    function testIncreasingRatio() public {
        qiUSDC.setExchangeRate(1200000000000000000); // 1 qiUSDC = 1.2 USDC ratio

        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - 1e8);

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        uint256 preBalance = vault.balanceOf(USER);
        uint256 preQIUSDCBalance = qiUSDC.balanceOf(address(vault));

        vm.startPrank(USER);
        qiUSDC.approve(address(vault), MAX_INT);
        vault.deposit(USER, MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preQIUSDCBalance + 50 * 1e8);
        assertTrue(vault.balanceOf(USER) == preBalance + 50 * 1e18);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 preVaultBalance = qiUSDC.balanceOf(address(vault)) + 50 * 1e8;

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);

        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // Assume WAVAX is 50$ and qiUSDC to USDC ratio is 1.2, so, it makes 375 qiUSDC.
        // %20 of the qiUSDC goes to the fee recipient (admin).
        uint256 adminFee = 75 * 1e8;
        uint256 callerFee = 375 * 1e8 / 100;
        assertTrue(qiUSDC.balanceOf(FEE_RECIPIENT) == adminFee);
        assertTrue(qiUSDC.balanceOf(address(this)) == callerFee);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preVaultBalance + ((375 * 1e8) - adminFee - callerFee));
    }

    function testIncreasingRatio2() public {
        qiUSDC.setExchangeRate(1200000000000000000); // 1 qiUSDC = 1.2 USDC ratio

        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - 1e8);

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        uint256 preBalance = vault.balanceOf(USER);
        uint256 preQIUSDCBalance = qiUSDC.balanceOf(address(vault));

        vm.startPrank(USER);
        qiUSDC.approve(address(vault), MAX_INT);
        vault.deposit(USER, MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preQIUSDCBalance + 50 * 1e8);
        assertTrue(vault.balanceOf(USER) == preBalance + 50 * 1e18);
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);

        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // However, it should be (%20 * 60min) + (%20 * 60min) = 12 WAVAX rewards in 1h stale.
        // Assume WAVAX is 50$ and qiUSDC to USDC ratio is 1.2. So, with the correct accounting it should be 500 qiUSDC.
        // %20 of the qiUSDC goes to the fee recipient.
        assertTrue(qiUSDC.balanceOf(FEE_RECIPIENT) != (100 * 1e8)); // expected to fail because of the accounting error
    }

    function testIncRatioDuringPeriod() public {
        vault.deposit(address(this), MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == 50 * 1e8);
        assertTrue(vault.balanceOf(address(this)) == 50 * 1e18 - 1e8);

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        uint256 preBalance = vault.balanceOf(USER);
        uint256 preQIUSDCBalance = qiUSDC.balanceOf(address(vault));

        vm.startPrank(USER);
        qiUSDC.approve(address(vault), MAX_INT);
        vault.deposit(USER, MINT_AMT / 2);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preQIUSDCBalance + 50 * 1e8);
        assertTrue(vault.balanceOf(USER) == preBalance + 50 * 1e18);
        vm.stopPrank();

        qiUSDC.setExchangeRate(1200000000000000000); // 1 qiUSDC = 1.2 USDC ratio

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 preVaultBalance = qiUSDC.balanceOf(address(vault)) + 50 * 1e8;

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);

        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // Assume WAVAX is 50$ and qiUSDC to USDC ratio is 1.2, so, it makes 375 qiUSDC.
        // %20 of the qiUSDC goes to the fee recipient (admin).
        uint256 adminFee = 75 * 1e8;
        uint256 callerFee = 375 * 1e8 / 100;
        assertTrue(qiUSDC.balanceOf(FEE_RECIPIENT) == adminFee);
        assertTrue(qiUSDC.balanceOf(address(this)) == callerFee);
        assertTrue(qiUSDC.balanceOf(address(vault)) == preVaultBalance + ((375 * 1e8) - adminFee - callerFee));
    }
}
