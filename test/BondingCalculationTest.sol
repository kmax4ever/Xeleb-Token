// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "../contracts/BondingTest.sol";

contract BondingCalculationTest is Test {
    function testCalculateBondingParameters() public {
        // Parameters for calculation
        uint256 maxSupply = 750_000_000e18; // 750M tokens
        uint256 bondingTarget = 24e18; // 24 ETH
        uint256 numberOfUses = 1000;

        // Calculate initial price and scaling factor
        UD60x18 targetPrice = ud(bondingTarget);
        UD60x18 maxSupplyUD = ud(maxSupply);
        UD60x18 initialPrice = ud(1e6); // Start with a very low price (0.000001 ETH)

        // Calculate slope needed to reach target price
        UD60x18 slope = targetPrice.sub(initialPrice).div(maxSupplyUD);

        // Calculate the correct scaling factor to reach target price at max supply
        // At max supply: targetPrice = slope * maxSupply / scalingFactor + initialPrice
        // Therefore: scalingFactor = slope * maxSupply / (targetPrice - initialPrice)
        UD60x18 scalingFactor = slope.mul(maxSupplyUD).div(
            targetPrice.sub(initialPrice)
        );

        console.log("Calculated Parameters:");
        console.log("Max Supply:", maxSupply);
        console.log("Bonding Target (ETH):", bondingTarget);
        console.log("Initial Price (ETH):", initialPrice.unwrap());
        console.log("Required Scaling Factor:", scalingFactor.unwrap());

        // Test with current contract parameters
        BondingTest bonding = new BondingTest();

        // Test key price points
        uint256[] memory percentages = new uint256[](6);
        percentages[0] = 0; // Start
        percentages[1] = 20; // Early
        percentages[2] = 40; // Early-mid
        percentages[3] = 60; // Mid
        percentages[4] = 80; // Late
        percentages[5] = 100; // Max supply

        for (uint i = 0; i < percentages.length; i++) {
            uint256 supplyPoint = (maxSupply * percentages[i]) / 100;
            // Simulate buying tokens up to this point
            if (supplyPoint > 0) {
                bonding.buyTokens{value: 1 ether}();
            }
            uint256 price = bonding.getCurrentPrice();
            console.log("At", percentages[i], "% of max supply:");
            console.log("  Supply:", supplyPoint);
            console.log("  Price:", price);

            if (percentages[i] == 100) {
                require(
                    price >= bondingTarget,
                    "Final price should reach bonding target"
                );
            }
        }
    }

    function testPriceProgression() public {
        BondingTest bonding = new BondingTest();

        // Test buying tokens in small increments
        uint256 buyAmount = 0.01 ether;
        uint256 totalBought = 0;

        for (uint i = 0; i < 10; i++) {
            bonding.buyTokens{value: buyAmount}();
            uint256 price = bonding.getCurrentPrice();
            console.log("Buy", i + 1, "Price:", price);
            totalBought += buyAmount;
        }

        console.log("Total ETH spent:", totalBought);
        console.log("Final price:", bonding.getCurrentPrice());
    }

    function testBuyTokensWithExcessETH() public {
        BondingTest bonding = new BondingTest();

        // Test buying with excess ETH
        uint256 buyAmount = 1 ether; // Send 1 ETH
        uint256 initialBalance = address(this).balance;

        bonding.buyTokens{value: buyAmount}();

        uint256 finalBalance = address(this).balance;
        uint256 price = bonding.getCurrentPrice();
        uint256 expectedTokens = buyAmount / price;

        console.log("Initial Balance:", initialBalance);
        console.log("Final Balance:", finalBalance);
        console.log("Price:", price);
        console.log("Expected Tokens:", expectedTokens);
        console.log("Actual Tokens:", bonding.totalSoldAmount());
        console.log("Total Raised:", bonding.totalRaisedAmount());

        // Verify that excess ETH was refunded
        uint256 expectedRefund = buyAmount -
            (bonding.totalSoldAmount() * price);
        require(
            finalBalance == initialBalance - buyAmount + expectedRefund,
            "Incorrect refund amount"
        );
    }
}
