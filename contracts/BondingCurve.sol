// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./AiAgentToken.sol";
import "hardhat/console.sol";
import "./lib/SafeMath.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
contract BondingCurve is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    AiAgentToken public agentToken;

    // PancakeSwap interfaces
    IUniswapV2Router01 public immutable pancakeSwapRouter;
    address public pair;

    // Bonding curve parameters
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint256 public constant PRICE_SCALING_FACTOR = 358999e21;
    uint256 public MAX_SUPPLY; // 700M tokens
    uint256 public constant BONDING_TARGET = 24e18; // 24 ETH target price
    uint256 public constant INITIAL_PRICE = 565e6; // 0.000000000765 ETH initial price
    UD60x18 public SLOPE; // Slope of the linear curve

    // Trading fees
    uint256 public constant FEE_PERCENT = 10; // 1%
    uint256 public constant BURN_PERCENT = 10; // 1%

    uint256 public constant DENOMINATOR = 1000;

    uint256 public constant MAX_BUY_PERCENT = 50;
    uint256 private MAX_BUY_AMOUNT;

    uint256 public constant ROUND_PERCENT = 10;

    // Trading limits
    uint256 public constant MAX_BUY_AMOUNT_PER_TX = 1_000_000_000 * 1e18; // 1M tokens per transaction
    uint256 public constant MAX_SELL_AMOUNT_PER_TX = 1_000_000_000 * 1e18; // 1M tokens per transaction
    address public constant PANCAKE_SWAP_ROUTER_V2 =
        0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    // max buy of user

    // Time-based restrictions
    uint256 public constant TRADE_COOLDOWN = 0;
    mapping(address => uint256) public lastTradeTime;
    uint256 public totalSoldAmount = 0;
    uint256 public totalRaisedAmount = 0;

    event LiquidityAdded(
        address indexed provider,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );

    event TokensPurchased(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 timestamp
    );
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );

    event Trade(
        address indexed trader,
        uint256 amount,
        UD60x18 price,
        uint256 timestamp
    );

    constructor(
        address _token,
        address initialOwner,
        uint256 initSupply
    ) Ownable(initialOwner) {
        require(_token != address(0), "Invalid token address");
        require(initSupply > 0, "Invalid supply");
        agentToken = AiAgentToken(_token);
        MAX_SUPPLY = initSupply;
        MAX_BUY_AMOUNT = (initSupply * MAX_BUY_PERCENT) / DENOMINATOR;
        pancakeSwapRouter = IUniswapV2Router01(PANCAKE_SWAP_ROUTER_V2);

        UD60x18 targetPrice = ud(BONDING_TARGET);
        UD60x18 initialPrice = ud(INITIAL_PRICE);
        UD60x18 maxSupply = ud(initSupply);

        SLOPE = targetPrice.sub(initialPrice).div(maxSupply);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (totalSoldAmount == 0) {
            return INITIAL_PRICE;
        }
        // Linear curve formula: P = m⋅S + b
        // Where:
        // P = Current price
        // m = SLOPE
        // S = totalSoldAmount (in wei)
        // b = INITIAL_PRICE
        UD60x18 currentSupply = ud(totalSoldAmount);
        UD60x18 initialPrice = ud(INITIAL_PRICE);

        // Calculate price using linear curve formula
        // P = m⋅S + b
        // totalSoldAmount is already in wei, so we need to divide by 1e18 to get actual supply
        UD60x18 currentPrice = SLOPE
            .mul(currentSupply.div(ud(PRICE_DENOMINATOR)))
            .add(initialPrice)
            .div(ud(PRICE_SCALING_FACTOR));
        return currentPrice.unwrap();
    }

    function calculatePurchaseReturn(
        uint256 _ethAmount
    ) public view returns (uint256) {
        uint256 price = getCurrentPrice();
        console.log("calculatePurchaseReturn PRICE", price);
        require(price > 0, "Invalid price");

        // Calculate tokens: tokenAmount = ethAmount / price
        // We need to adjust for decimals since price is in wei
        UD60x18 ethAmount = ud(_ethAmount);
        UD60x18 currentPrice = ud(price);
        UD60x18 tokenAmount = ethAmount.div(currentPrice);

        if (totalSoldAmount == 0 && tokenAmount.unwrap() > MAX_BUY_AMOUNT) {
            tokenAmount = ud(MAX_BUY_AMOUNT);
        }

        return tokenAmount.unwrap();
    }

    function calculateSaleReturn(
        uint256 tokenAmount
    ) public view returns (uint256) {
        uint256 price = getCurrentPrice();
        require(price > 0, "Invalid price");

        UD60x18 tokens = ud(tokenAmount);
        UD60x18 currentPrice = ud(price);
        UD60x18 ethAmount = tokens.mul(currentPrice).div(ud(PRICE_DENOMINATOR));
        return ethAmount.unwrap();
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        // For sure not over MAX_SUPPLY
        uint256 tokenAmount = calculatePurchaseReturn(_ethAmount);

        if (totalSoldAmount == MAX_BUY_AMOUNT) {
            return tokenAmount / 2;
        }
        uint256 nextRaised = totalRaisedAmount.add(_ethAmount).add(10000); // round
        if (
            totalSoldAmount.add(tokenAmount) >= MAX_SUPPLY ||
            nextRaised >= BONDING_TARGET
        ) {
            //ROUND buy amount
            uint remaingAmount = MAX_SUPPLY.sub(totalSoldAmount);
            if (
                remaingAmount <
                MAX_SUPPLY.mul(ROUND_PERCENT).div(DENOMINATOR) &&
                nextRaised >= BONDING_TARGET
            ) {
                return remaingAmount;
            }

            uint256 rate = (
                _ethAmount.mul(PRICE_DENOMINATOR).add(totalRaisedAmount)
            ) / BONDING_TARGET;
            tokenAmount = remaingAmount.mul(rate).div(PRICE_DENOMINATOR);
        }
        if (totalSoldAmount.add(tokenAmount) > MAX_SUPPLY) {
            tokenAmount = MAX_SUPPLY.sub(totalSoldAmount);
        }
        return tokenAmount;
    }

    function getETHForTokens(
        uint256 tokenAmount
    ) public view returns (uint256) {
        uint256 ethAmount = calculateSaleReturn(tokenAmount);
        // for sure not over balance
        if (totalRaisedAmount < ethAmount) {
            ethAmount = totalRaisedAmount;
        }
        return ethAmount;
    }

    // Buy tokens with ETH
    function buyTokens() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        require(
            block.timestamp >= lastTradeTime[msg.sender].add(TRADE_COOLDOWN),
            "Too soon"
        );

        uint256 tokenAmount = getTokensForETH(msg.value);
        require(tokenAmount <= MAX_BUY_AMOUNT_PER_TX, "Exceeds max buy");
        require(
            totalSoldAmount.add(tokenAmount) <= MAX_SUPPLY,
            "Exceeds available supply"
        );

        uint256 burnAmount = tokenAmount.mul(BURN_PERCENT).div(DENOMINATOR);
        uint256 remainingAmount = tokenAmount.sub(burnAmount);

        // Create vesting schedule
        agentToken.createVestingScheduleForBuyer(msg.sender, remainingAmount);

        totalSoldAmount = totalSoldAmount.add(tokenAmount);
        totalRaisedAmount = totalRaisedAmount.add(msg.value);
        agentToken.burn(msg.sender, burnAmount);

        lastTradeTime[msg.sender] = block.timestamp;
        emit TokensPurchased(
            msg.sender,
            msg.value,
            tokenAmount,
            block.timestamp
        );
        UD60x18 currentPrice = ud(msg.value).div(ud(tokenAmount));
        emit Trade(msg.sender, tokenAmount, currentPrice, block.timestamp);
    }

    // Sell tokens for ETH
    function sellTokens(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Amount must be > 0");
        require(
            agentToken.balanceOf(msg.sender) >= tokenAmount,
            "Insufficient balance"
        );
        require(tokenAmount <= MAX_SELL_AMOUNT_PER_TX, "Exceeds max sell");
        require(
            block.timestamp >= lastTradeTime[msg.sender].add(TRADE_COOLDOWN),
            "Too soon"
        );

        uint256 refundAmount = getETHForTokens(tokenAmount);
        require(
            address(this).balance >= refundAmount,
            "Insufficient contract balance"
        );

        uint256 burnAmount = tokenAmount.mul(BURN_PERCENT).div(DENOMINATOR);
        uint256 remainingAmount = tokenAmount.sub(burnAmount);

        agentToken.burn(msg.sender, remainingAmount);
        agentToken.burn(msg.sender, burnAmount);

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "ETH transfer failed");

        lastTradeTime[msg.sender] = block.timestamp;
        totalSoldAmount = totalSoldAmount.sub(tokenAmount);
        totalRaisedAmount = totalRaisedAmount.sub(refundAmount);
        emit TokensSold(msg.sender, tokenAmount, refundAmount, block.timestamp);

        UD60x18 currentPrice = ud(refundAmount).div(ud(tokenAmount));
        emit Trade(msg.sender, tokenAmount, currentPrice, block.timestamp);
    }

    // View functions
    function getRaisedAmount() public view returns (uint256) {
        return totalRaisedAmount;
    }

    function getTotalSoldAmount() public view returns (uint256) {
        return totalSoldAmount;
    }

    function creatorBuy(
        address buyer,
        uint256 ethValue,
        uint256 tokenAmount
    ) external onlyOwner {
        totalSoldAmount = totalSoldAmount.add(tokenAmount);
        totalRaisedAmount = totalRaisedAmount.add(ethValue);

        emit TokensPurchased(buyer, ethValue, tokenAmount, block.timestamp);
        UD60x18 currentPrice = ud(ethValue).div(ud(tokenAmount));
        emit Trade(buyer, tokenAmount, currentPrice, block.timestamp);
    }

    // Emergency functions
    receive() external payable {}
    fallback() external payable {}

    // Add liquidity to PancakeSwap
    function addLiquidity() external payable {
        // Approve router to spend tokens
        // require(
        //     totalRaisedAmount >= BONDING_TARGET,
        //     "Not enought bonding target!"
        // );
        uint256 tokenAmount = agentToken.balanceOf(address(this));
        uint256 nativeBalance = address(this).balance;
        agentToken.approve(address(pancakeSwapRouter), tokenAmount);
        // Add liquidity to PancakeSwap
        (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        ) = pancakeSwapRouter.addLiquidityETH{value: nativeBalance}(
                address(agentToken),
                tokenAmount,
                0, // Accept any amount of tokens
                nativeBalance, // Accept any amount of ETH
                msg.sender,
                block.timestamp
            );

        emit LiquidityAdded(
            msg.sender,
            amountToken,
            amountETH,
            block.timestamp
        );
    }
}
