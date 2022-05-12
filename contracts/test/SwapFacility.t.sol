// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/SwapFacility.sol";
import "./TestERC20.sol";
import "./TestXAnchor.sol";

contract TestSwapFacility is DSTest {

    ERC20 public aUST;
    TestERC20 public UST;
    TestXAnchor public xAnchor;
    SwapFacility public sFacility;
    TestAggregatorV3 public priceFeed;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public ustAmt = 1248325249482323000;
    uint256 public aUSTAmt = 1000000000000000000;

    function setUp() public {
        UST = new TestERC20(
            "Wormhole USD Token",
            "UST",
            18
        );
        priceFeed = new TestAggregatorV3();
        priceFeed.setPrice(1248325249482323000);
        xAnchor = new TestXAnchor(
            address(UST),
            address(priceFeed)
        );
        aUST = ERC20(address(xAnchor));
        sFacility = new SwapFacility(
            address(UST),
            address(aUST),
            address(xAnchor),
            address(priceFeed)
        );
        sFacility.setSwapper(msg.sender, true);
        UST.mint(address(this), ustAmt);
        UST.mint(address(sFacility), ustAmt);
        UST.approve(address(sFacility), ustAmt);
        UST.approve(address(xAnchor), ustAmt);
        aUST.approve(address(sFacility), aUSTAmt);
        aUST.approve(address(xAnchor), aUSTAmt);
    }

    function testPriceFeed() public {
        uint256 expectedPrice = 1248325249482323000;
        (
        /*uint80 roundID*/,
        int256 price,
        /*uint256  startedAt*/,
        /*uint256  timeStamp*/,
        /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        assertTrue(expectedPrice == uint256(price));
    }

    // Fuzz test
    function testSwapAmountOut(uint256 _fee) public {
        vm.assume(_fee > 0);
        vm.assume(_fee < 31);

        uint256 fee = _fee * 100;
        sFacility.setFee(fee);

        uint256 depositedUST = 1248325249482323000;
        uint256 amountOut = 12483252494823230;

        xAnchor.depositStable(address(UST), depositedUST);
        assertTrue(UST.balanceOf(address(this)) == (ustAmt - depositedUST));

        vm.roll(block.number + 5); //simulates relayer's delay

        xAnchor.depositStableStep2(address(this), depositedUST);
        assertTrue(aUST.balanceOf(address(this)) == xAnchor.getAmountIn(depositedUST));

        uint256 aUSTBalance = aUST.balanceOf(address(sFacility));
        uint256 preAUST = aUST.balanceOf(address(this));
        sFacility.swapAmountOut(amountOut);
        uint256 deductedAUST = (xAnchor.getAmountIn(amountOut)) * 10000 / (10000 - fee); // swap fee
        uint256 postAUST = preAUST - deductedAUST;
        assertTrue(UST.balanceOf(address(this)) == amountOut);
        assertTrue(aUST.balanceOf(address(this)) == postAUST);

        vm.roll(block.number + 5); //simulates relayer's delay

        uint256 aUSTNewBalance = aUSTBalance + deductedAUST;
        uint256 preUST = UST.balanceOf(address(sFacility));
        xAnchor.redeemStableStep2(address(sFacility), aUSTNewBalance);
        uint256 postUST = preUST + xAnchor.getAmountOut(aUSTNewBalance);
        assertTrue(UST.balanceOf(address(sFacility)) == postUST);
        assertTrue(aUST.balanceOf(address(sFacility)) == 0);
    }

    // Fuzz test
    function testSwapAmountIn(uint256 _fee) public {
        vm.assume(_fee > 0);
        vm.assume(_fee < 31);

        uint256 fee = _fee * 100;
        sFacility.setFee(fee);

        uint256 depositedUST = 1248325249482323000;
        uint256 amountIn = 10000000000000000;

        xAnchor.depositStable(address(UST), depositedUST);
        assertTrue(UST.balanceOf(address(this)) == (ustAmt - depositedUST));

        vm.roll(block.number + 5); //simulates relayer's delay

        xAnchor.depositStableStep2(address(this), depositedUST);
        assertTrue(aUST.balanceOf(address(this)) == xAnchor.getAmountIn(depositedUST));

        uint256 aUSTBalance = aUST.balanceOf(address(sFacility));
        uint256 preAUST = aUST.balanceOf(address(this));
        sFacility.swapAmountIn(amountIn);
        uint256 postAUST = preAUST - amountIn;
        uint256 amountOut = xAnchor.getAmountOut(amountIn * (10000 - fee) / 10000);
        assertTrue(UST.balanceOf(address(this)) == amountOut);
        assertTrue(aUST.balanceOf(address(this)) == postAUST);

        vm.roll(block.number + 5); //simulates relayer's delay

        uint256 aUSTNewBalance = aUSTBalance + amountIn;
        uint256 preUST = UST.balanceOf(address(sFacility));
        xAnchor.redeemStableStep2(address(sFacility), aUSTNewBalance);
        uint256 postUST = preUST + xAnchor.getAmountOut(aUSTNewBalance);
        assertTrue(UST.balanceOf(address(sFacility)) == postUST);
        assertTrue(aUST.balanceOf(address(sFacility)) == 0);
    }

    function testWithDifferentPriceFeed() public {
        priceFeed.setPrice(1156454584544248500);

        uint256 fee = 1 * 100;
        sFacility.setFee(fee);

        uint256 depositedUST = 1248325249482323000;
        uint256 amountIn = 10000000000000000;

        xAnchor.depositStable(address(UST), depositedUST);
        assertTrue(UST.balanceOf(address(this)) == (ustAmt - depositedUST));

        vm.roll(block.number + 5); //simulates relayer's delay

        xAnchor.depositStableStep2(address(this), depositedUST);
        assertTrue(aUST.balanceOf(address(this)) == xAnchor.getAmountIn(depositedUST));

        uint256 aUSTBalance = aUST.balanceOf(address(sFacility));
        uint256 preAUST = aUST.balanceOf(address(this));
        sFacility.swapAmountIn(amountIn);
        uint256 postAUST = preAUST - amountIn;
        uint256 amountOut = xAnchor.getAmountOut(amountIn * (10000 - fee) / 10000);
        assertTrue(UST.balanceOf(address(this)) == amountOut);
        assertTrue(aUST.balanceOf(address(this)) == postAUST);

        vm.roll(block.number + 5); //simulates relayer's delay

        uint256 aUSTNewBalance = aUSTBalance + amountIn;
        uint256 preUST = UST.balanceOf(address(sFacility));
        xAnchor.redeemStableStep2(address(sFacility), aUSTNewBalance);
        uint256 postUST = preUST + xAnchor.getAmountOut(aUSTNewBalance);
        assertTrue(UST.balanceOf(address(sFacility)) == postUST);
        assertTrue(aUST.balanceOf(address(sFacility)) == 0);
    }

    function testRemove() public {
        UST.mint(address(sFacility), ustAmt);

        uint256 preUST = UST.balanceOf(address(this));
        uint256 postUST = preUST + ustAmt;
        sFacility.remove(ustAmt);
        assertTrue(UST.balanceOf(address(this)) == postUST);
    }

    function testAccessControls() public {
        vm.startPrank(0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB);

        vm.expectRevert("Ownable: caller is not the owner");
        sFacility.remove(ustAmt);

        vm.expectRevert("Ownable: caller is not the owner");
        sFacility.setFee(1111111);

        vm.expectRevert("Ownable: caller is not the owner");
        sFacility.setSwapper(0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB, true);

        vm.stopPrank();
    }

    function testSwapOverCapacity() public {
        xAnchor.depositStableStep2(address(this), ustAmt);

        vm.expectRevert("SF: Not enough UST");
        sFacility.swapAmountOut(ustAmt + 100);

        vm.expectRevert("SF: Not enough UST");
        sFacility.swapAmountIn(aUSTAmt + 100);
    }

    function testNotApprovedSwap() public {
        vm.startPrank(0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB);

        vm.expectRevert("SF: Not approved to swap");
        sFacility.swapAmountOut(12483252494823230);

        vm.expectRevert("SF: Not approved to swap");
        sFacility.swapAmountIn(10000000000000000);

        vm.stopPrank();
    }
}
