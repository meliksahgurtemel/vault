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

    TestcToken public usdc;
    CompVault public vault;
    TestRewardController public rewardController;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ADMIN_FEE = 2000;
    uint256 public CALLER_FEE = 100;
    uint256 public MAX_REINVEST_STALE = 1 hours;
    uint256 public MAX_INT = 2**256 - 1;
    uint256 public MINT_AMT = 100 * 1e18;

    address public FEE_RECIPIENT = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address public USER = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;

    function setUp() public {
        usdc = new TestcToken(
            "USD Coin",
            "USDC",
            18
        );
        rewardController = new TestRewardController(
            "Wrapped AVAX",
            "WAVAX",
            18
        );
        vault = new CompVault();
        vault.initialize(
            address(usdc),
            "Vault",
            "VAULT",
            ADMIN_FEE,
            CALLER_FEE,
            MAX_REINVEST_STALE,
            address(rewardController),
            address(rewardController)
        );
        usdc.mint(address(this), MINT_AMT);
        usdc.mint(USER, MINT_AMT);
        usdc.approve(address(vault), MAX_INT);

        vault.pushRewardToken(address(rewardController));
        vault.setFeeRecipient(FEE_RECIPIENT);
    }

    function testAccError() public {
        vault.deposit(address(this), MINT_AMT / 2);
        console.log(vault.balanceOf(address(this)));

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        vm.startPrank(USER);
        usdc.approve(address(vault), MAX_INT);
        vault.deposit(address(this), MINT_AMT / 2);
        console.log(vault.balanceOf(address(this)));
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);
        console.log(usdc.balanceOf(FEE_RECIPIENT));
        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // Assume WAVAX is 50$ and it makes 450 USDC.
        // %20 of the USDC goes to the fee recipient.
        assertTrue(usdc.balanceOf(FEE_RECIPIENT) == (90 * 1e18));
    }

    function testAccError2() public {
        vault.deposit(address(this), MINT_AMT / 2);
        console.log(vault.balanceOf(address(this)));

        vm.warp(vault.lastReinvestTime() + 1800); // plus 30 min

        vm.startPrank(USER);
        usdc.approve(address(vault), MAX_INT);
        vault.deposit(address(this), MINT_AMT / 2);
        console.log(vault.balanceOf(address(this)));
        vm.stopPrank();

        vm.warp(vault.lastReinvestTime() + 3601);

        uint256 totalRewards = (1*1e17) * (30 + 60); // assume 0.1 WAVAX rewards are given every min.
        rewardController.setRewardAmt(totalRewards);
        vault.deposit(address(this), MINT_AMT / 2);
        console.log(usdc.balanceOf(FEE_RECIPIENT));
        // In 1h stale, there are 2 depositors but one of them deposited 30 min before the stale is finished.
        // Since one depositer deposited in the middle, there are rewards for only %20 * 30min from that deposit.
        // So, (%20 * 30min) + (%20 * 60min) = 9 WAVAX rewards in total.
        // However, it should be (%20 * 60min) + (%20 * 60min) = 12 WAVAX rewards.
        // Assume WAVAX is 50$ and with the correct accounting it makes 600 USDC.
        // %20 of the USDC goes to the fee recipient.
        assertTrue(usdc.balanceOf(FEE_RECIPIENT) == (120 * 1e18)); // expected to fail
    }
}
