//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {Dscengine} from "../src/Dscengine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
contract DeployDsc is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function run() external returns (DecentralizedStableCoin,Dscengine,HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        
        ///使用指定的私钥部署合约
        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        Dscengine dscengine = new Dscengine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc));
        ///让 Dscengine 成为 DSC 的管理员，从而可以安全地控制 DSC 的铸造、燃烧和其他管理操作。
        dsc.transferOwnership(address(dscengine));   
        vm.stopBroadcast();
        return (dsc,dscengine,helperConfig);
    }
}