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
    uint256 public MAX_SUPPLY; // 700M tokens

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

    uint32 public reserveRatio = 253002;

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
        MAX_SUPPLY = initSupply;
        INITIAL_PRICE = (BONDING_TARGET * PRICE_DENOMINATOR) / MAX_SUPPLY;
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
            totalSoldAmount + tokenAmount <= MAX_SUPPLY,
            "Exceeds available supply"
        );

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / BURN_DENOMINATOR;
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

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / BURN_DENOMINATOR;
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

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        if (totalSoldAmount == 0) {
            return INITIAL_PRICE * _ethAmount;
        } else {
            uint256 tokenAmount = calculatePurchaseReturn(
                MAX_SUPPLY,
                address(this).balance,
                uint32(reserveRatio),
                _ethAmount
            );
            // for sure not over MAX_SUPPLY
            if (totalSoldAmount + tokenAmount > MAX_SUPPLY) {
                tokenAmount = MAX_SUPPLY - totalSoldAmount;
            }
            return tokenAmount;
        }
    }

    function getETHForTokens(
        uint256 tokenAmount
    ) public view returns (uint256) {
        uint256 ethAmount = calculateSaleReturn(
            MAX_SUPPLY,
            address(this).balance,
            uint32(reserveRatio),
            tokenAmount
        );
        // for sure not over balance
        if (address(this).balance < ethAmount) {
            ethAmount = address(this).balance;
        }
        return ethAmount;
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

    function getCurrentPrice() public view returns (uint256) {
        uint256 ethAmount = 1e10;
        uint256 tokenAmount = getTokensForETH(ethAmount);
        console.log("ethAmount", ethAmount);
        console.log("tokenAmount", tokenAmount);
        return (ethAmount * 1e18) / tokenAmount;
    }
}
//TODO
// important : bonding curve price
// FEE TU BONDING SEND TO STAKING
