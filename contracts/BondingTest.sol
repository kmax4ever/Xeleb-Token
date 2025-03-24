// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "hardhat/console.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "./lib/SafeMath.sol";

contract BondingTest {
    using SafeMath for uint256;
    // Constants with increased precision
    uint256 public constant INITIAL_PRICE = 765e7; // 0.00000000765 ETH
    uint256 public constant MAX_SUPPLY = 700_000_000e18; // 700M tokens
    uint256 public constant PRICE_SCALING_FACTOR = 348999e21; // Increased from 1e25 for more precision
    uint256 public constant BONDING_TARGET = 24e18; // 24 ETH
    UD60x18 public SLOPE;
    uint256 public totalSoldAmount;
    uint256 public totalRaisedAmount;

    constructor() {
        // Calculate slope with increased precision
        UD60x18 targetPrice = ud(BONDING_TARGET);
        UD60x18 initialPrice = ud(INITIAL_PRICE);
        UD60x18 maxSupply = ud(MAX_SUPPLY);

        // Calculate slope with higher precision
        SLOPE = targetPrice.sub(initialPrice).div(maxSupply);

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
        uint256 price = getCurrentPrice();
        require(price > 0, "Invalid price");

        // Use higher precision for token calculation
        UD60x18 ethAmount = ud(_ethAmount);
        UD60x18 currentPrice = ud(price);

        // Calculate token amount with increased precision
        UD60x18 tokenAmount = ethAmount.div(currentPrice);

        // Round down to avoid dust amounts
        return tokenAmount.unwrap();
    }

    function buyTokens() public payable {
        require(msg.value > 0, "Must send ETH");

        // Calculate tokens with increased precision
        uint256 tokenAmount = getTokensForETH(msg.value);
        require(tokenAmount > 0, "Invalid token amount");
        if (tokenAmount + totalSoldAmount > MAX_SUPPLY) {
            tokenAmount = MAX_SUPPLY - totalSoldAmount;
        }
        // Update state with precise amounts
        totalSoldAmount = totalSoldAmount.add(tokenAmount);
        totalRaisedAmount = totalRaisedAmount.add(msg.value);

        console.log("totalRaisedAmount", totalRaisedAmount);
        console.log("totalSoldAmount", totalSoldAmount);
    }
}
