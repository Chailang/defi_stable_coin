// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Test } from "forge-std/Test.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

import { MockV3Aggregator } from "../../mocks/MockV3Aggregator.sol";
import { Dscengine } from "../../../src/Dscengine.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { console } from "forge-std/console.sol";

/**
 * @title StopOnRevertHandler
 * @author xxxx 
 * @notice Foundry 的模糊测试（fuzzing/invariant testing） 中的“Handler”合约，
 * 专门模拟外部用户（actors）去和 DSCEngine、DecentralizedStableCoin 交互。
 * 这样测试框架就能自动随机调用这些函数，帮助发现系统中的边界情况和潜在 bug。
 * 测试目标：验证 DSCEngine（去中心化稳定币引擎）的安全性和鲁棒性。
 * Handler 角色：在 Foundry 的 invariant 测试里，Handler 合约模拟用户的行为（如存款、赎回、转账、清算、更新预言机价格等）。
 * StopOnRevert 命名：说明这是个 遇到 revert 就停止 的 Handler，用来调试问题。
 * 
 */

contract StopOnRevertHandler is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Deployed contracts to interact with
    Dscengine public dscEngine;
    DecentralizedStableCoin public dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(Dscengine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        //通过 DSCEngine 拿到抵押品地址（假设 0 号是 WETH，1 号是 WBTC）。
        //通过 getCollateralTokenPriceFeed 获取对应的价格预言机。
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    // 方法交互

    ///////////////
    // DSCEngine //
    ///////////////

    /**
     * 
     * @param collateralSeed 随机种子，用于选择抵押品（WETH 或 WBTC）
     * @param amountCollateral 抵押品的数量
     */
    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // must be more than 0
        // bound 限制 amountCollateral 在 1 到 MAX_DEPOSIT_SIZE 之间
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        //根据随机种子选择抵押品 (0 号是 WETH，1 号是 WBTC)
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        //伪造用户 (vm.prank)
        vm.startPrank(msg.sender);
        //铸造代币 比如ETH 或 WBTC
        collateral.mint(msg.sender, amountCollateral);
        //授权引擎花费代币 比如ETH 或 WBTC
        collateral.approve(address(dscEngine), amountCollateral);
        //存入引擎
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }
    /**
     * 
     * @param collateralSeed 随机种子，用于选择抵押品（WETH 或 WBTC）
     * @param amountCollateral 赎回的抵押品数量
     */
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        //选择抵押品
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        //获取用户在引擎中的最大可赎回抵押品数量
        uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        //限制赎回数量在 0 到 maxCollateral 之间
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        //vm.prank(msg.sender);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        //引擎赎回
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }
    /**
     * 
     * @param amountDsc 想要燃烧的 DSC 数量
     */
    function burnDsc(uint256 amountDsc) public {
        //用户最多只能燃烧自己持有的 DSC
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        if (amountDsc == 0) {
            return;
        }
        //授权引擎去燃烧用户的 DSC
        vm.startPrank(msg.sender);
        dsc.approve(address(dscEngine), amountDsc);
        dscEngine.burnDsc(amountDsc);
        vm.stopPrank();
    }

    // Only the DSCEngine can mint DSC!
    // function mintDsc(uint256 amountDsc) public {
    //     amountDsc = bound(amountDsc, 0, MAX_DEPOSIT_SIZE);
    //     vm.prank(dsc.owner());
    //     dsc.mint(msg.sender, amountDsc);
    // }

    /**
     * 
     * @param collateralSeed 随机种子，用于选择抵押品（WETH 或 WBTC）
     * @param userToBeLiquidated 目标用户地址
     * @param debtToCover 想要偿还的债务数量
     * @notice 模拟别人清算该用户的抵押品。
     */
    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        //获取最小健康因子和目标用户的健康因子
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        //获取用户的健康因子
        uint256 userHealthFactor = dscEngine.getHealthFactor(userToBeLiquidated);
        //如果用户健康因子 >= 最小健康因子，说明用户不需要被清算，直接返回
        if (userHealthFactor >= minHealthFactor) {
            return;
        }
        //限制偿还债务在 1 到 uint96 最大值之间
        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
        // 获取抵押品
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        //清算
        dscEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /////////////////////////////
    // DecentralizedStableCoin //
    /////////////////////////////

    //转账稳定币
    function transferDsc(uint256 amountDsc, address to) public {
        //避免转账到 0 地址。
        if (to == address(0)) {
            to = address(1);
        }
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        vm.prank(msg.sender);
        //模拟普通用户间的 DSC 转账。
        dsc.transfer(to, amountDsc);
    }

    /////////////////////////////
    // Aggregator //
    /////////////////////////////

    //更新抵押品价格（模拟预言机波动）
    function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
        int256 intNewPrice = int256(uint256(newPrice));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(collateral)));
        priceFeed.updateAnswer(intNewPrice);
    }

    /// Helper Functions
    // 随机决定测试用 WETH 或 WBTC。
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}