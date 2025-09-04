// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity 0.8.30;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
/*
*@title DSCEngine
*该系统的设计尽可能地最小化，并让代币始终保持1个代币==1美元的挂钩。
*这是一种具有以下属性的稳定币：
*-外源性抵押
*-美元挂钩
*-算法稳定
*
*如果DAI没有治理、没有费用，并且只得到WETH和WBTC的支持，那么它与DAI类似。
*我们的DSC系统应该始终“过镀”。在任何时候，都不应该 所有抵押品<所有DSC的美元支持价值。
*@notice此合约是去中心化稳定币系统的核心。它处理所有的逻辑
*用于铸造和赎回DSC，以及存放和提取抵押品。
*@notice本合同基于MakerDAO DSS系统
*/
contract Dscengine is ReentrancyGuard{

    ///////////////////
    // Errors
    ///////////////////
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();


    ///////////////////
    // Types
    ///////////////////

    // using ... for ... 是 Solidity 的语法，用于 为某个类型附加库函数。
    // 这里的意思是：将 OracleLib 库中的函数，附加给 AggregatorV3Interface 类型的变量。
    // 这样，任何 AggregatorV3Interface 类型的实例都可以像调用成员函数一样直接调用库里的函数。
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////

    DecentralizedStableCoin private immutable i_dsc;
    // 清算阈值 = 50  意思是：你必须超额抵押 200%（资产价值要至少是债务的两倍） 
    // 算法：collateral * 50% ≥ debt  
    // 也就是抵押品要是负债的两倍以上
    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    // 清算奖励 = 10
    // 意思是：清算人（liquidator）在清算时可以以 90% 的价格买到被清算人的抵押品
    // 换句话说，清算人有 10% 的折扣，激励他们去执行清算操作
    uint256 private constant LIQUIDATION_BONUS = 10; 
    // 清算精度 = 100
    // 通常用来配合百分比计算，比如 50 / 100 = 50%
    // 避免小数，直接用整数来表示百分比，方便计算
    uint256 private constant LIQUIDATION_PRECISION = 100;
    // 最小健康因子 = 1 * 10^18
    // 表示用户仓位的安全程度（health factor）最低要 ≥ 1，否则就可能被清算
    // 一般健康因子 > 1 表示安全，< 1 表示仓位不健康
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    //精度 1e18 = 10^18 位
    uint256 private constant PRECISION = 1e18;
    //价格为1e8 = 10^8 位 （大多数链上价格源的精度） 需要添加的精度
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    //大多数链上价格源的精度
    uint256 private constant FEED_PRECISION = 1e8;

    /// @dev 存储用户铸造的 DSC 数量
    mapping(address user => uint256 desAmount) private s_dscMinted;

    /// @dev 存储每种抵押代币对应的价格源地址，便于合约获取代币的价格
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev 这个嵌套映射用来 记录每个用户每种代币的抵押数量。
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if
        // redeemFrom != redeemedTo, then it was liquidated

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    //确保传入的代币地址是允许作为抵押品的代币 
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }
    ///////////////////
    // Functions
    ///////////////////

    /**
     * @param tokenAddresses      存入的抵押品 ERC20 代币地址
     * @param priceFeedAddresses  对应的价格地址
     * @param dscAddress          稳定币的地址
     * @notice 初始化函数
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // These feeds will be the USD pairs
        // For example ETH / USD or MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    /**
     * @param tokenCollateralAddress 你要存入的抵押品 ERC20 代币地址
     * @param amountCollateral 你要存入的抵押品数量
     * @notice 允许用户把指定 ERC20 代币存入合约作为抵押品
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {   
        //更新合约内部记录，增加用户在该代币上的抵押数量
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        //触发事件，记录存入操作，方便前端监听或链上日志查询。
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        //调用 ERC20 的 transferFrom 方法，把用户钱包中的代币转到合约地址。
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
     /*
     * @param tokenCollateralAddress: 地址
     * @param amountCollateral: 数量
     * @notice 赎回抵押品
     * @notice 销毁后才可以铸造
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
     /*
     * @notice 注意！你将销毁你的DSC
     * @dev 如果你担心自己可能会被清算，但又想销毁你的 DSC 同时保留抵押品，那么你可能会用到这个功能。
     */
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); 
    }

     /**
    //  * @param amountDscToMint  铸造稳定币的数量
    //  * @notice 铸造稳定币 DSC  抵押价值必须大于等于铸造的 DSC 价值
    //  */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        //确保用户在铸造新的 DSC 之前，抵押品的价值足够覆盖新的债务
        _revertIfHealthFactorIsBroken(msg.sender);
        //调用 DSC 合约的 mint 方法，铸造新的 DSC 代币到用户钱包地址
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }

    }

    ///////////////////
    // external
    ///////////////////

     /*
     * @param tokenCollateralAddress 抵押品代币地址
     * @param amountCollateral: 抵押品数量
     * @param amountDscToMint: 铸造的 DSC 数量
     * @notice 抵押代币去铸造稳定币 
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    /*
     * @param tokenCollateralAddress 抵押品代币地址
     * @param amountCollateral: 赎回的抵押品数量
     * @param amountDscToBurn: 销毁的 DSC 数量
     * @notice 赎回抵押品并销毁稳定币 
     */
    function redeemCollateralAndBurnDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);

    }
   
   
    ///////////////////
    // public
    ///////////////////

    ///////////////////
    // internal
    ///////////////////

    ///////////////////
    // private
    ///////////////////

    /**
     * @param collateral 抵押代币的地址
     * @param user 用户地址 
     * @param debtToCover 还债的 DSC 数量
     * @notice 清算不健康的用户
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    )
        external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {   
        //1.检查用户是否真的不健康 调用 _healthFactor(user) 看看用户的健康因子。
        //如果用户的健康因子大于等于最小值（MIN_HEALTH_FACTOR），说明还能撑得住，不允许被清算 → 抛错。
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //2.计算需要拿多少抵押品
        //举例：假如清算人愿意烧掉 100 DSC 来替 insolvent user 还债。
        //那么就要算出 100 USD 等值的抵押品（比如 ETH）。
        //会根据价格预言机算出：100 美元等于多少个 ETH。
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        //3.加上清算奖励
        //协议会多给清算人 10% 的抵押品。
        //所以清算人烧掉 100 DSC → 实际能拿到 110 USD 等值的抵押品。
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        //4.执行抵押品转移 _redeemCollateral
        // 从被清算用户的抵押品余额里扣掉（比如 110 美元等值的 ETH）。
        // 然后把这些抵押品直接转给清算人。
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        //5.销毁 DSC _burnDsc
        // 被清算用户的借款记录 s_DSCMinted[user] 减少 100（等于 debtToCover）。
        // 清算人把 100 DSC 转到合约里。
        // 合约再把这 100 DSC 销毁掉。
        _burnDsc(debtToCover, user, msg.sender);
        
        //6.检查清算后健康因子
        // 确保被清算用户的健康因子比清算前高（说明债务减少，情况改善）。
        // 果没改善，抛错（理论上不会发生）。
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        //7.检查清算人自己的健康因子
        //确保清算人不会因为拿太多抵押品，自己变成不健康。
        _revertIfHealthFactorIsBroken(msg.sender);
    }


     /**
     * @param tokenCollateralAddress 你要赎回的抵押品 ERC20 代币地址
     * @param amountCollateral 你要赎回的抵押品数量
     * @param from 被清算人地址 表示抵押品是从哪个用户的余额里扣掉的。比如：在清算时，被清算的用户是 Alice，那么 from = Alice。
     * @param to   清算人地址 表示抵押品最终要转到谁的钱包地址。在清算时，抵押品是要奖励给清算人（比如 Bob），所以 to = Bob。合约会实际调用 ERC20 的 transfer(to, amountCollateral)，把抵押品打给 Bob。
     * @notice 允许任何人清算债务人的债务 , from 和 to 是为了表示 抵押品从谁那里扣除 → 转给谁。
     */
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    )
        private
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        //检查用户在该代币上的抵押数量是否足够
        uint256 userBalance = s_collateralDeposited[from][tokenCollateralAddress];
        if (userBalance < amountCollateral) {
            revert DSCEngine__TransferFailed();
        }
        //更新合约内部记录，减少清算用户在该代币上的抵押数量
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        //确保赎回后用户的健康因子仍然符合要求，防止用户通过赎回抵押品来降低健康因子，导致仓位不安全
        _revertIfHealthFactorIsBroken(from);
        //触发事件，记录赎回操作，方便前端监听或链上日志查询。
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        //调用 ERC20 的 transfer 方法，把合约地址的代币转回到 清算 用户钱包地址。
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
    //  * @param amountDscToBurn  销毁稳定币的数量
    //  * @param onBehalfOf 债务人地址
    //  * @param dscFrom 清算人地址
    //  * @notice 还债 + 销毁代币 允许清算人帮债务人还债 
    //  */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private moreThanZero(amountDscToBurn) nonReentrant {
        //减少债务人的 DSC 数量，更新内部记录
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        //从清算人地址扣除相应数量的 DSC
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn); 
        if (!success) { 
            revert DSCEngine__TransferFailed();
        } 
        //调用 DSC 合约的 burn 方法，销毁 DSC 代币
        i_dsc.burn(amountDscToBurn);  
    }

    /**
    //  * @param user  用户地址
    //  * @return totalDscMinted  用户铸造的 DSC 数量
    //  * @return collateralValueInUsd  用户抵押品的美元价值
    //  * @notice 获取用户的铸币数量和抵押品价值
    //  */
    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     * 
     * @param user 用户地址
     * @notice 检查用户的健康因子是否低于预设的最小值，如果是则交易会被拒绝
     */
    function _revertIfHealthFactorIsBroken(address user) private view {
        //计算用户当前的健康因子
        uint256 userHealthFactor = _healthFactor(user);
        //健康因子必须大于等于预设的最小值，否则交易会被拒绝
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    /**
     * 
     * @param user 用户地址
     * @return 健康因子数值
     * @notice 计算并返回用户的健康因子，健康因子越高表示抵押品越充足
     */
    function _healthFactor(address user) private view returns (uint256) {
        //获取用户的铸币数量和抵押品价值
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    /**
     * 
     * @param totalDscMinted 用户铸造的 DSC 数量
     * @param collateralValueInUsd 用户抵押品的美元价值
     * @return 健康因子数值
     * @notice 根据用户的铸币数量和抵押品价值计算健康因子
     */
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) private pure returns (uint256) {
        if (totalDscMinted == 0) {
            //如果用户没有铸造任何 DSC，健康因子被视为无限大，表示非常安全
            return type(uint256).max;
        }
        //健康因子 = (抵押品价值 * 清算阈值) / 铸币数量 
        //清算阈值通常小于100 表示需要超额抵押
        //计算有效抵押品价值 (抵押品的50%价值)  
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        //计算健康因子
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        /**
            collateralValueInUsd = 2000（用户抵押价值 2000 美元）
            totalDscMinted = 1500（用户借出 1000 DSC）
            LIQUIDATION_THRESHOLD = 50（50%）
            LIQUIDATION_PRECISION = 100
            RECISION = 1e18（健康因子精度） 
            
            collateralAdjustedForThreshold=  2000×50/1000 = 1000 
            说明按照 50% 的清算阈值，抵押品有效价值是 1000 美元。
            
            healthFactor=  (1000×1e18)/1500 = 0.666...×1e18 ≈ 6.66e17
            说明用户的健康因子约为 0.666，低于 1，表示仓位不健康，可能面临清算风险。
            需要注意的是，这只是一个示例，实际数值会根据用户的抵押品价值和借出数量变化。
            这个计算帮助系统评估用户仓位的安全性，确保抵押品足以覆盖借出的 DSC。  

            健康因子 = 1e18 → 刚好等于安全线
            健康因子 > 1e18 → 超过安全线，抵押充足
            健康因子 < 1e18 → 低于安全线，有被清算风险  
        */
        
        
    }
    ///////////////////
    // view & pure functions
    ///////////////////
    /**
     * 
     * @param token 抵押代币地址
     * @param amount 抵押代币数量
     * @return 该数量抵押代币的美元价值
     * @notice 获取指定数量的抵押代币的美元价值
     */
    function getUSDTValue(address token, uint256 amount) public view returns (uint256) {
        address priceFeedAddress = s_priceFeeds[token];
        if (priceFeedAddress == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
         AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 价格为8位精度
        // 数量为18位精度
        // 精度对齐
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
    /**
     * 
     * @param user 用户地址
     * @notice 获取用户所有抵押品的总价值
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //遍历所有允许的抵押代币
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            //获取用户在该代币上的抵押数量
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                //获取该代币的美元价值，并累加到总价值中
                totalCollateralValueInUsd += getUSDTValue(token, amount);
            }
        }
        return totalCollateralValueInUsd;
    }
    /**
     * 
     * @param token 抵押代币地址
     * @param usdAmountInWei 美元数量，精度为 1e18
     * @return 需要多少该抵押代币才能兑换指定的美元数量
     * @notice 根据美元价值计算需要多少抵押代币
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // 用来获取代币对 USD 的价格。 
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // Chainlink 的大多数 USD 价格对有 8 位小数，比如：ETH/USD = 2000 USD 返回值 = 2000 * 1e8 = 200000000000
        //计算代币数量
        //PRECISION 用于统一单位，通常是 1e18，因为我们习惯用 18 位小数表示金额。
        //ADDITIONAL_FEED_PRECISION 用于调整价格的精度，因为价格通常是 8 位小数，我们需要把它调整到 18 位小数。 通常设置为 1e10，因为 1e18 / 1e8 = 1e10，保证单位匹配。
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}