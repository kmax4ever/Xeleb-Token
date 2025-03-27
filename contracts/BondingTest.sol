// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "hardhat/console.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "./lib/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
contract BondingTest is ReentrancyGuard {
    using SafeMath for uint256;
    // Constants with increased precision
    uint256 public constant INITIAL_PRICE = 765e7; // 0.00000000765 ETH
    uint256 public constant MAX_SUPPLY = 750_000_000e18; // 700M tokens
    uint256 public constant PRICE_SCALING_FACTOR = 349999e21; // Increased from 1e25 for more precision
    uint256 public constant BONDING_TARGET = 24e18; // 24 ETH
    UD60x18 public SLOPE;
    uint256 public totalSoldAmount;
    uint256 public totalRaisedAmount;
    uint256 public constant MAX_BUY_PERCENT = 50;
    uint256 private MAX_BUY_AMOUNT;
    uint256 public constant DENOMINATOR = 1000;
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint256 public constant ROUND_PERCENT = 5;

    constructor() {
        // Calculate slope with increased precision
        UD60x18 targetPrice = ud(BONDING_TARGET);
        UD60x18 initialPrice = ud(INITIAL_PRICE);
        UD60x18 maxSupply = ud(MAX_SUPPLY);

        // Calculate slope with higher precision
        SLOPE = targetPrice.sub(initialPrice).div(maxSupply);
        MAX_BUY_AMOUNT = (MAX_SUPPLY * MAX_BUY_PERCENT) / DENOMINATOR;
        console.log("Initial Price (ETH):", INITIAL_PRICE);
        console.log("Max Supply (tokens):", MAX_SUPPLY);
        console.log("Target Price (ETH):", BONDING_TARGET);
        console.log("Slope:", SLOPE.unwrap());
    }

    function getCurrentPrice() public view returns (uint256) {
        if (totalSoldAmount == 0) {
            return INITIAL_PRICE;
        }

        // Linear curve formula with increased precision: P = m⋅S + b
        UD60x18 currentSupply = ud(totalSoldAmount);
        UD60x18 initialPrice = ud(INITIAL_PRICE);

        // Calculate price with higher precision
        UD60x18 currentPrice = SLOPE.mul(currentSupply).add(initialPrice).div(
            ud(PRICE_SCALING_FACTOR)
        );

        return currentPrice.unwrap();
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        // for sure not over MAX_SUPPLY
        uint256 tokenAmount = calculatePurchaseReturn(_ethAmount);

        if (totalSoldAmount.add(tokenAmount) >= MAX_SUPPLY) {
            uint remaingAmount = MAX_SUPPLY.sub(totalSoldAmount);
            if (
                remaingAmount < MAX_SUPPLY.mul(ROUND_PERCENT).div(DENOMINATOR)
            ) {
                return remaingAmount;
            }

            uint256 rate = (
                (_ethAmount.mul(PRICE_DENOMINATOR) + totalRaisedAmount)
            ) / BONDING_TARGET;
            tokenAmount = remaingAmount.mul(rate).div(PRICE_DENOMINATOR);
        }
        // if (totalSoldAmount.add(tokenAmount) > MAX_SUPPLY) {
        //     tokenAmount = MAX_SUPPLY.sub(totalSoldAmount);
        // }
        return tokenAmount;
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

    function buyTokens() public payable nonReentrant {
        require(msg.value > 0, "Must send ETH");

        uint256 tokenAmount = getTokensForETH(msg.value);
        require(tokenAmount > 0, "Invalid token amount");

        uint256 excessETH = 0;
        // Check if we would exceed max supply
        if (tokenAmount + totalSoldAmount > MAX_SUPPLY) {
            tokenAmount = MAX_SUPPLY - totalSoldAmount;
            // Refund excess ETH
            excessETH = msg.value - (tokenAmount * getCurrentPrice());
            if (excessETH > 0) {
                payable(msg.sender).transfer(excessETH);
            }
        }

        // Update state with precise amounts
        totalSoldAmount = totalSoldAmount.add(tokenAmount);
        totalRaisedAmount = totalRaisedAmount.add(msg.value - excessETH);

        console.log("totalRaisedAmount", totalRaisedAmount);
        console.log("totalSoldAmount", totalSoldAmount);
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
    function sellToken(uint256 tokenAmount) public payable {
        require(msg.value > 0, "Must send ETH");

        // Calculate tokens with increased precision
        uint256 ethRefund = getETHForTokens(tokenAmount);
        totalSoldAmount -= tokenAmount;
        totalRaisedAmount -= ethRefund;
    }
}
