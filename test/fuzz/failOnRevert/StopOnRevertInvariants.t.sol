// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

// Invariants:
// protocol must never be insolvent / undercollateralized
// TODO: users cant create stablecoins with a bad health factor
// TODO: a user should only be able to be liquidated if they have a bad health factor

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Dscengine } from "../../../src/Dscengine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../../script/HelperConfig.s.sol";
import { DeployDsc } from "../../../script/DeployDsc.s.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { StopOnRevertHandler } from "./StopOnRevertHandler.t.sol";
import { console } from "forge-std/console.sol";

/**
 * @title StopOnRevertInvariants
 * @author xxxx
 * @notice Foundry 的模糊测试（fuzzing/invariant testing） 中的“不停下来的” invariant 合约，
 * 就是专门配合 StopOnRevertHandler 做 Foundry 不变量测试（invariant testing） 的测试合约
 * 专门用来验证 DSCEngine、DecentralizedStableCoin 在各种极端输入组合下的安全性和鲁棒性。
 * 测试目标：验证 DSCEngine（去中心化稳定币引擎）的安全性和鲁棒性。
 * Invariant 角色：在 Foundry 的 invariant 测试里，Invariant 合约定义了一些必须始终保持为真的条件（invariants），
 * 例如“协议总是有足够的抵押品支持所有铸造的稳定币”。
 * StopOnRevert 命名：说明这是个 遇到 revert 就停止 的 Invariant，用来调试问题。
 * 
 * 提供了 两个不变量（invariants）：
 * 1. 协议持有的抵押品总价值 必须 大于等于 铸造的稳定币总价值。
 * 2. 所有的 getter 函数都不应该 revert。
 * 
 * 这些不变量会在 Foundry Invariant Testing 中被反复验证。
 * 主要目的是：验证在极端输入组合下，DSCEngine 不会出现安全性问题（比如抵押不足不清算、资金丢失等）。
 * 
 */
contract StopOnRevertInvariants is StdInvariant, Test {
    Dscengine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    StopOnRevertHandler public handler;

    function setUp() external {
        DeployDsc deployer = new DeployDsc();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        //创建 handler，并通过 targetContract(address(handler)) 指定 fuzz 测试只会调用 handler 中的函数。
        handler = new StopOnRevertHandler(dsce, dsc);
        targetContract(address(handler));
        // targetContract(address(ethUsdPriceFeed)); Why can't we just do this?
    }
    //核心不变量：协议不能破产
    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
        //协议持有的抵押品总价值 必须 大于等于 铸造的稳定币总价值。
        //铸造的稳定币总价值 = DSC 的总供应量（totalSupply）
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));
        //用价格预言机算出抵押品总价值
        uint256 wethValue = dsce.getUSDTValue(weth, wethDeposted);
        uint256 wbtcValue = dsce.getUSDTValue(wbtc, wbtcDeposited);
        //抵押品总价值 = 协议持有的 WETH 价值 + 协议持有的 WBTC 价值
        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);

        assert(wethValue + wbtcValue >= totalSupply);
    }
    //辅助不变量：所有的 getter 函数都不应该 revert。
    // 确保无论系统状态怎么变，基础信息查询都不会崩溃。
    function invariant_gettersCantRevert() public view {
        dsce.getAdditionalFeedPrecision();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getDsc();
        // dsce.getTokenAmountFromUsd();
        // dsce.getCollateralTokenPriceFeed();
        // dsce.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}