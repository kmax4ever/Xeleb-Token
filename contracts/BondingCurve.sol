// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./AiAgentToken.sol";
import "hardhat/console.sol";
import "./lib/SafeMath.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
contract BondingCurve is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    AiAgentToken public agentToken;

    // Bonding curve parameters
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint256 public MAX_SUPPLY; // 700M tokens
    uint256 public constant BONDING_TARGET = 24e18; // 24 ETH target price
    uint256 public constant INITIAL_PRICE = 765e7; // 0.00000000765 ETH initial price
    UD60x18 public SLOPE; // Slope of the linear curve

    // Trading fees
    uint256 public constant FEE_PERCENT = 10; // 1%
    uint256 public constant BURN_PERCENT = 10; // 1%
    uint256 public constant DENOMINATOR = 1000;

    // Trading limits
    uint256 public constant MAX_BUY_AMOUNT = 1_000_000_000 * 1e18; // 1M tokens per transaction
    uint256 public constant MAX_SELL_AMOUNT = 1_000_000_000 * 1e18; // 1M tokens per transaction

    // Time-based restrictions
    uint256 public constant TRADE_COOLDOWN = 0;
    mapping(address => uint256) public lastTradeTime;
    uint256 public totalSoldAmount = 0;

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
        uint256 price,
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
Ç
        UD60x18 targetPrice = ud(BONDING_TARGET);
        UD60x18 initialPrice = ud(INITIAL_PRICE);
        UD60x18 maxSupply = ud(MAX_SUPPLY);

Ç
        SLOPE = targetPrice.sub(initialPrice).div(maxSupply);

        console.log("INITIAL_PRICE", INITIAL_PRICE);
        console.log("MAX_SUPPLY", MAX_SUPPLY);
        console.log("BONDING_TARGET", BONDING_TARGET);
    }

    function getCurrentPrice() public view returns (uint256) {

        if (totalSoldAmount == 0) {
            return INITIAL_PRICE;
        }

        UD60x18 currentSupply = ud(totalSoldAmount);
        UD60x18 initialPrice = ud(INITIAL_PRICE);

        UD60x18 price = SLOPE.mul(currentSupply).add(initialPrice);
        return price.unwrap();
    }

    function calculatePurchaseReturn(
        uint256 _ethAmount
    ) public view returns (uint256) {
        uint256 price = getCurrentPrice();
        require(price > 0, "Invalid price");


        UD60x18 ethAmount = ud(_ethAmount);
        UD60x18 currentPrice = ud(price);
        UD60x18 tokenAmount = ethAmount.mul(ud(PRICE_DENOMINATOR)).div(
            currentPrice
        );
        return tokenAmount.unwrap();
    }

    function calculateSaleReturn(
        uint256 tokenAmount
    ) public view returns (uint256) {
        uint256 price = getCurrentPrice();
        require(price > 0, "Invalid price");

        UD60x18 tokens = ud(tokenAmount);
        UD60x18 currentPrice = ud(price);
        UD60x18 ethAmount = tokens.mul(currentPrice).div(ud(1e18));

        return ethAmount.unwrap();
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        // for sure not over MAX_SUPPLY
        uint256 tokenAmount = calculatePurchaseReturn(_ethAmount);
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
        if (address(this).balance < ethAmount) {
            ethAmount = address(this).balance;
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
        require(tokenAmount <= MAX_BUY_AMOUNT, "Exceeds max buy");
        require(
            totalSoldAmount.add(tokenAmount) <= MAX_SUPPLY,
            "Exceeds available supply"
        );

        uint256 burnAmount = tokenAmount.mul(BURN_PERCENT).div(DENOMINATOR);
        uint256 remainingAmount = tokenAmount.sub(burnAmount);

        // Create vesting schedule
        agentToken.createVestingScheduleForBuyer(msg.sender, remainingAmount);

        totalSoldAmount = totalSoldAmount.add(tokenAmount);
        agentToken.burn(msg.sender, burnAmount);

        lastTradeTime[msg.sender] = block.timestamp;
        emit TokensPurchased(
            msg.sender,
            msg.value,
            tokenAmount,
            block.timestamp
        );

        emit Trade(msg.sender, tokenAmount, getCurrentPrice(), block.timestamp);
    }

    // Sell tokens for ETH
    function sellTokens(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Amount must be > 0");
        require(
            agentToken.balanceOf(msg.sender) >= tokenAmount,
            "Insufficient balance"
        );
        require(tokenAmount <= MAX_SELL_AMOUNT, "Exceeds max sell");
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

        emit TokensSold(msg.sender, tokenAmount, refundAmount, block.timestamp);
        emit Trade(msg.sender, tokenAmount, getCurrentPrice(), block.timestamp);
    }

    // View functions
    function getRaisedAmount() public view returns (uint256) {
        return address(this).balance;
    }

    function getTotalSoldAmount() public view returns (uint256) {
        return totalSoldAmount;
    }

    function creatorBuyEvent(
        address buyer,
        uint256 ethValue,
        uint256 tokenAmount
    ) external onlyOwner {
        emit TokensPurchased(buyer, ethValue, tokenAmount, block.timestamp);
        emit Trade(buyer, tokenAmount, ethValue, block.timestamp);
    }

    // Emergency functions
    receive() external payable {}
    fallback() external payable {}
}
