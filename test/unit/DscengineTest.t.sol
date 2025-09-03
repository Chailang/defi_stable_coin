// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Dscengine } from "../../src/Dscengine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { Test, console } from "forge-std/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
contract DscengineTest is Test{
    DecentralizedStableCoin dsc;
    Dscengine dscengine;
    HelperConfig config;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    function setUp() public {
        DeployDsc deployer = new DeployDsc();
        (dsc,dscengine,config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
    }

    //////////////////
    // Price Tests //
    //////////////////
    function testGetUsdValue() public view{
        uint256 ethAmount = 15e18;
        // 模拟价格
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscengine.getUSDTValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }
}