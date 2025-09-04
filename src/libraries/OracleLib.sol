// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


/*
 * @title OracleLib
 * @author xxx
 * @notice 用于检测 Chainlink 价格是否过时（stale）。
 * 如果价格过时，函数会 revert，导致 DSCEngine 无法使用，这是有意设计，为了安全。
 * 设计哲学：如果价格数据失效，不要让协议继续运行，避免错误操作。
 */
library OracleLib {
    //定义了自定义错误 OracleLib__StalePrice，比字符串 revert 更节省 gas。
    error OracleLib__StalePrice();
    //设置价格超时阈值为 3 小时。
    //超过这个时间没有更新，就认为价格过时。
    uint256 private constant TIMEOUT = 3 hours;
    /*
     * @param chainlinkFeed Chainlink 价格预言机合约地址
     * @notice 检查 Chainlink 价格是否过时
     * @dev 如果价格过时，函数会 revert，防止 DSCEngine 继续操作
     * @return 与 AggregatorV3Interface.latestRoundData 相同的返回值
     */
    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        // roundId：轮次 ID
        // answer：价格
        // startedAt：轮次开始时间
        // updatedAt：价格最后更新时间
        // answeredInRound：价格计算所在轮次
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            chainlinkFeed.latestRoundData();
        //如果价格从未更新过，或者最新价格的计算轮次小于当前轮次，认为价格过时
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }
        //计算价格距当前时间的秒数
        uint256 secondsSince = block.timestamp - updatedAt;
        //如果超过 TIMEOUT（3 小时），认为价格过时并 revert
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getTimeout(AggregatorV3Interface /* chainlinkFeed */ ) public pure returns (uint256) {
        return TIMEOUT;
    }
}