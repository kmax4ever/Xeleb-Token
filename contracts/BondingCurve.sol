// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./AiAgentToken.sol";
import "hardhat/console.sol";
import "./lib/BancorFormula.sol";
contract BondingCurve is BancorFormula, Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeMath for uint256;
    AiAgentToken public agentToken;

    // Bonding curve parameters
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint256 public INITIAL_PRICE = 0; // Will be set in constructor
    uint256 public INITIAL_SUPPLY; // 700M tokens

    uint256 public constant GROWTH_RATE = 2;

    // Trading fees
    uint256 public constant BURN_PERCENT = 10; // 1%
    uint256 public constant BURN_DENOMINATOR = 1000;

    // Price protection
    uint256 public constant MAX_BUY_PRICE_IMPACT = 100; // 10%
    uint256 public constant MAX_SELL_PRICE_IMPACT = 100; // 10%

    // Trading limits
    uint256 public constant MAX_BUY_AMOUNT = 1000000000 * 1e18; //  tokens
    uint256 public constant MAX_SELL_AMOUNT = 1000000000 * 1e18; //  tokens

    // lock , vesting config
    uint256 public constant BUY_UNLOCK_PERCENT = 1000; // 1%
    uint256 public constant VESTING_PERCENT = 9000; //0.1%
    uint256 public constant ENOMINATOR = 10000;

    // Time-based restrictions
    uint256 public constant TRADE_COOLDOWN = 0;
    mapping(address => uint256) public lastTradeTime;
    uint256 public totalSoldAmount = 0;
    // Treasury
    uint256 public constant BONDING_TARGET = 24 ether;

    uint256 public scale = 10 ** 18;
    uint256 public reserveBalance = 10 * scale;
    uint32 public reserveRatio = 293502;

    event TokensPurchased(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 ethAmount
    );
    event PriceUpdate(uint256 newPrice);

    constructor(
        address _token,
        address initialOwner,
        uint256 initSupply
    ) Ownable(initialOwner) {
        require(_token != address(0), "Invalid token address");
        agentToken = AiAgentToken(_token);
        INITIAL_SUPPLY = initSupply;
        INITIAL_PRICE = (BONDING_TARGET * PRICE_DENOMINATOR) / INITIAL_SUPPLY;
        console.log("INITIAL_PRICE", INITIAL_PRICE);
    }

    // Buy tokens with ETH
    function buyTokens() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        if (address(this).balance >= BONDING_TARGET) {
            //TODO handle add liquid
        }
        // require(address(this).balance <= BONDING_TARGET, "Completed bonding!");
        require(
            block.timestamp >= lastTradeTime[msg.sender] + TRADE_COOLDOWN,
            "Too soon"
        );

        uint256 tokenAmount = getTokensForETH(msg.value);
        //require(tokenAmount <= MAX_BUY_AMOUNT, "Exceeds max buy");
        require(
            totalSoldAmount + tokenAmount <= INITIAL_SUPPLY,
            "Exceeds available supply"
        );

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / BURN_DENOMINATOR;
        uint256 remainingAmount = tokenAmount - burnAmount;
        // Create vesting schedule
        agentToken.createVestingScheduleForBuyer(msg.sender, remainingAmount);

        totalSoldAmount += tokenAmount;
        agentToken.burn(msg.sender, burnAmount);

        lastTradeTime[msg.sender] = block.timestamp;
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
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

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / BURN_DENOMINATOR;
        uint256 remainingAmount = tokenAmount - burnAmount;

        agentToken.burn(msg.sender, remainingAmount);
        agentToken.burn(msg.sender, burnAmount);

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "ETH transfer failed");

        lastTradeTime[msg.sender] = block.timestamp;
        totalSoldAmount -= tokenAmount;

        emit TokensSold(msg.sender, tokenAmount, refundAmount);
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        if (totalSoldAmount == 0) {
            return INITIAL_PRICE * _ethAmount;
        } else {
            return
                calculatePurchaseReturn(
                    INITIAL_SUPPLY,
                    address(this).balance,
                    uint32(reserveRatio),
                    _ethAmount
                );
        }
    }

    function getETHForTokens(
        uint256 tokenAmount
    ) public view returns (uint256) {
        return
            calculateSaleReturn(
                INITIAL_SUPPLY,
                address(this).balance,
                uint32(reserveRatio),
                tokenAmount
            );
    }

    // Emergency functions
    receive() external payable {}
    fallback() external payable {}

    function getRaisedAmount() public view returns (uint256) {
        return address(this).balance;
    }
    function getTotalSoldAmount() public view returns (uint256) {
        return totalSoldAmount;
    }
    function increaseTotalSold(uint256 amout) external onlyOwner {
        totalSoldAmount += amout;
    }
}
//TODO
// important : bonding curve price
// FEE TU BONDING SEND TO STAKING
