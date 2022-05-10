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
        xAnchor = new TestXAnchor(
            address(UST),
            address(priceFeed),
            1248325249482323000 //set the price feed of aUST
        );
        aUST = ERC20(address(xAnchor));
        sFacility = new SwapFacility(
            address(UST),
            address(aUST),
            address(xAnchor),
            address(priceFeed)
        );
        sFacility.setFee(100);
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

    function testSwapAmountOut() public {
        uint256 depositedUST = 10000;
        xAnchor.depositStable(address(UST), depositedUST);
        assertTrue(UST.balanceOf(address(this)) == (ustAmt - depositedUST));

        vm.roll(block.number + 5);

        xAnchor.depositStableStep2(depositedUST);
        assertTrue(aUST.balanceOf(address(this)) == xAnchor.getAmountIn(depositedUST));

        sFacility.swapAmountOut(depositedUST);

        uint256 amtAUST = xAnchor.getAmountIn(depositedUST);
        xAnchor.redeemStableStep2(amtAUST);
        console.log(aUST.balanceOf(address(this)));
    }
}
