// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Upgradeable} from "solmate/tokens/ERC20Upgradeable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {TestAggregatorV3} from "./TestAggregatorV3.sol";

contract TestXAnchor is ERC20Upgradeable {

    ERC20 public immutable UST;
    TestAggregatorV3 public immutable priceFeed;

    constructor(
        address _UST,
        address _priceFeed,
        int256 _price
    ) {
        UST = ERC20(_UST);
        priceFeed = TestAggregatorV3(_priceFeed);
        priceFeed.setPrice(_price);
        initializeERC20("Anchor Terra USD", "aUST", 6);
    }

    function _getUSTaUST() internal view returns (uint256) {
        (
        /*uint80 roundID*/,
        int256 price,
        /*uint256  startedAt*/,
        /*uint256  timeStamp*/,
        /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        return amountIn * _getUSTaUST() / 1e18;
    }

    function getAmountIn(uint256 amountOut) public view returns (uint256) {
        return 1e18 * amountOut / _getUSTaUST();
    }

    function depositStable(address token, uint256 amtUST) external {
        SafeTransferLib.safeTransferFrom(
            ERC20(token),
            msg.sender,
            address(this),
            amtUST
        );
    }

    function depositStableStep2(uint256 amtUST) external {
        uint256 amtAUST = getAmountIn(amtUST);
        _mint(msg.sender, amtAUST);
    }

    function redeemStable(address token, uint256 amtAUST) external {
        SafeTransferLib.safeTransferFrom(
            ERC20(token),
            msg.sender,
            address(this),
            amtAUST
        );
    }

    function redeemStableStep2(address to, uint256 amtAUST) external {
        uint256 amtUST = getAmountOut(amtAUST);

        SafeTransferLib.safeTransfer(
            UST,
            to,
            amtUST
        );
    }

    function withdrawAsset(string calldata token) external {
        uint256 amt = 10 * 1e18;

        SafeTransferLib.safeTransfer(
            UST,
            msg.sender,
            amt
        );
    }
}
