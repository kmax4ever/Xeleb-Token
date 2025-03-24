// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
import {BondingTest} from "../contracts/BondingTest.sol";
import {console2 as console} from "../lib/forge-std/src/console2.sol";

contract BondingTestTest is Test {
    BondingTest public bonding;

    function setUp() public {
        bonding = new BondingTest();
    }

    function testFullBondingCalculation() public {
        // Get the current price
        uint256 currentPrice = bonding.getCurrentPrice();
        console.log("Initial Price:", currentPrice);

        // Calculate expected tokens for 24 ETH
        uint256 expectedTokens = bonding.getTokensForETH(24e18);
        console.log("Expected tokens for 24 ETH:", expectedTokens);

        // Buy with 24 ETH
        bonding.buyTokens{value: 24e18}();

        // Get actual tokens sold
        uint256 actualTokens = bonding.totalSoldAmount();
        console.log("Actual tokens sold:", actualTokens);

        // Calculate difference
        int256 difference = int256(actualTokens) - int256(expectedTokens);
        console.log("Difference:", difference);

        // Verify the price after purchase
        uint256 finalPrice = bonding.getCurrentPrice();
        console.log("Final Price:", finalPrice);
    }
}
