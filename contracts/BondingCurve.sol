// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./AiAgentToken.sol";
import "hardhat/console.sol";

contract BondingCurve is Ownable, ReentrancyGuard {
    using Math for uint256;
    AiAgentToken public agentToken;

    // Bonding curve parameters
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint256 public MAX_SUPPLY; // 700M tokens
    uint256 public constant BONDING_TARGET = 24 ether;
    uint256 public INITIAL_PRICE = 1e7;
    uint256 public SLOPE;

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
    uint256 public totalSoldAmount = 1;

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
        agentToken = AiAgentToken(_token);

        // Set initial price to 0.00001 ETH
        INITIAL_PRICE = 1e7;
        MAX_SUPPLY = initSupply;
        console.log("INITIAL_PRICE", INITIAL_PRICE);

        // Calculate slope = (TARGET_PRICE - INITIAL_PRICE) / MAX_SUPPLY
        // For 24 ETH target price and 700M max supply
        SLOPE = 342857; // ((24e18 - 1e7) * 1e18) / (700M * 1e18)

        console.log("SLOPE", SLOPE);
    }

    function getCurrentPrice() public view returns (uint256) {
        // P = m⋅S + b
        // Where:
        // m = SLOPE (scaled by PRICE_DENOMINATOR)
        // S = totalSoldAmount
        // b = INITIAL_PRICE
        return ((SLOPE * totalSoldAmount) / PRICE_DENOMINATOR) + INITIAL_PRICE;
    }

    function getBuyPrice() public view returns (uint256) {
        uint256 basePrice = getCurrentPrice();
        return basePrice + ((basePrice * FEE_PERCENT) / DENOMINATOR);
    }

    function getSellPrice() public view returns (uint256) {
        if (totalSoldAmount <= 1e18) {
            return 0; // Prevent selling when supply is too low
        }
        uint256 basePrice = getCurrentPrice();
        return basePrice - ((basePrice * FEE_PERCENT) / DENOMINATOR);
    }

    function calculatePurchaseReturn(
        uint256 _ethAmount
    ) public view returns (uint256) {
        uint256 price = getBuyPrice();
        require(price > 0, "Invalid price");
        return (_ethAmount * PRICE_DENOMINATOR) / price;
    }

    function calculateSaleReturn(
        uint256 tokenAmount
    ) public view returns (uint256) {
        uint256 price = getSellPrice();
        require(price > 0, "Invalid price");
        return (tokenAmount * price) / PRICE_DENOMINATOR;
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        // for sure not over MAX_SUPPLY
        uint256 tokenAmount = calculatePurchaseReturn(_ethAmount);
        if (totalSoldAmount + tokenAmount > MAX_SUPPLY) {
            tokenAmount = MAX_SUPPLY - totalSoldAmount;
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
            block.timestamp >= lastTradeTime[msg.sender] + TRADE_COOLDOWN,
            "Too soon"
        );

        uint256 tokenAmount = getTokensForETH(msg.value);
        require(tokenAmount <= MAX_BUY_AMOUNT, "Exceeds max buy");
        require(
            totalSoldAmount + tokenAmount <= MAX_SUPPLY,
            "Exceeds available supply"
        );

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / DENOMINATOR;
        uint256 remainingAmount = tokenAmount - burnAmount;

        // Create vesting schedule
        agentToken.createVestingScheduleForBuyer(msg.sender, remainingAmount);

        totalSoldAmount += tokenAmount;
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
            block.timestamp >= lastTradeTime[msg.sender] + TRADE_COOLDOWN,
            "Too soon"
        );

        uint256 refundAmount = getETHForTokens(tokenAmount);
        require(
            address(this).balance >= refundAmount,
            "Insufficient contract balance"
        );

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / DENOMINATOR;
        uint256 remainingAmount = tokenAmount - burnAmount;

        agentToken.burn(msg.sender, remainingAmount);
        agentToken.burn(msg.sender, burnAmount);

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "ETH transfer failed");

        lastTradeTime[msg.sender] = block.timestamp;
        totalSoldAmount -= tokenAmount;

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
