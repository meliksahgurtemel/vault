// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

contract TestAggregatorV3 {

    int256 public price;

    function setPrice(int256 _price) external {
        price = _price;
    }

    function getRoundData(uint80 _roundId) external view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
        return (
            _roundId,
            price,
            0,
            0,
            0
        );
    }

  function latestRoundData() external view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
        return (
            0,
            price,
            0,
            0,
            0
        );
    }
}
