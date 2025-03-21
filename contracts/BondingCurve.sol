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
    uint256 private constant PRECISION = 10 ** 27;
    uint256 public constant PRICE_DENOMINATOR = 1e18;
    uint256 public MAX_SUPPLY; // 1 billion tokens
    uint256 public constant BONDING_TARGET = 24 ether;

    // Initial price = TARGET/MAX_SUPPLY = 24e18/1e27 = 2.4e-8 ether
    uint256 public INITIAL_PRICE; // 2.4e-8 ether * 1e18 (for precision)

    // Growth rate = ln(2400)/1B ≈ 7.8e-8
    uint256 public GROWTH_RATE; // 7.8e-8 * 1e9 (for precision)

    // Trading fees
    uint256 public constant FEE_PERCENT = 10; // 1%
    uint256 public constant BURN_PERCENT = 10; // 1%
    uint256 public constant DENOMINATOR = 1000;

    // Trading limits
    uint256 public constant MAX_BUY_AMOUNT = 1_000_000 * 1e18; // 1M tokens per transaction
    uint256 public constant MAX_SELL_AMOUNT = 1_000_000 * 1e18; // 1M tokens per transaction

    // Time-based restrictions
    uint256 public constant TRADE_COOLDOWN = 0;
    mapping(address => uint256) public lastTradeTime;
    uint256 public totalSoldAmount = 0;

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

    constructor(
        address _token,
        address initialOwner,
        uint256 initSupply
    ) Ownable(initialOwner) {
        require(_token != address(0), "Invalid token address");
        agentToken = AiAgentToken(_token);
        MAX_SUPPLY = initSupply;
        INITIAL_PRICE = (BONDING_TARGET * PRICE_DENOMINATOR) / initSupply;
        console.log("INITIAL_PRICE", INITIAL_PRICE);
        GROWTH_RATE =
            calculateGrowthRate(
                BONDING_TARGET * PRICE_DENOMINATOR,
                initSupply
            ) /
            PRECISION;

        console.log("GROWTH_RATE", GROWTH_RATE);
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
        // require(
        //     totalSoldAmount + tokenAmount <= MAX_SUPPLY,
        //     "Exceeds available supply"
        // );

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / DENOMINATOR;
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
        // require(tokenAmount <= MAX_SELL_AMOUNT, "Exceeds max sell");
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

        emit TokensSold(msg.sender, tokenAmount, refundAmount);
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        if (totalSoldAmount == 0) {
            console.log("INITIAL_PRICE2", INITIAL_PRICE);
            return (INITIAL_PRICE * _ethAmount) / DENOMINATOR;
        } else {
            return calculatePurchaseReturn(_ethAmount);
        }
    }

    function getETHForTokens(
        uint256 tokenAmount
    ) public view returns (uint256) {
        return calculateSaleReturn(tokenAmount);
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

    function getCurrentPrice(uint256 supply) public view returns (uint256) {
        // P = a * e^(b*S)
        // We use fixed-point arithmetic since Solidity doesn't support floating point
        // INITIAL_PRICE is already scaled by 1e18
        // GROWTH_RATE is scaled by 1e9
        // supply is in tokens (scaled by 1e18)

        // Calculate b*S first, reducing supply scale to handle the exponent
        uint256 exponent = (GROWTH_RATE * (supply / 1e9)) / 1e9;

        // Calculate e^(b*S) using a Taylor series approximation
        uint256 expTerm = 1e18; // Start with 1.0 in fixed point
        uint256 term = 1e18;

        for (uint i = 1; i <= 5; i++) {
            term = (term * exponent) / (i * 1e18);
            expTerm += term;
        }

        // Final price = INITIAL_PRICE * e^(b*S)
        return (INITIAL_PRICE * expTerm) / 1e18;
    }

    function _getBuyPrice() private view returns (uint256) {
        uint256 basePrice = getCurrentPrice(totalSoldAmount);
        return basePrice + ((basePrice * FEE_PERCENT) / DENOMINATOR);
    }

    function getSellPrice() public view returns (uint256) {
        if (totalSoldAmount <= 1e18) {
            return 0; // Prevent selling when supply is too low
        }
        uint256 basePrice = getCurrentPrice(totalSoldAmount);
        return basePrice - ((basePrice * FEE_PERCENT) / DENOMINATOR);
    }

    function calculatePurchaseReturn(
        uint256 _ethAmount
    ) public view returns (uint256) {
        uint256 price = _getBuyPrice();
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

    function ln(uint256 x) internal pure returns (uint256) {
        // ln(x) is only defined for x > 0
        require(x > 0, "Input must be greater than 0");

        // If x is very close to 1, return 0
        if (x == PRECISION) {
            return 0;
        }

        // For x < 1, use ln(x) = -ln(1/x)
        if (x < PRECISION) {
            return PRECISION * 2 - ln((PRECISION * PRECISION) / x);
        }

        // For large values, use ln(x) = ln(y * 2^k) = ln(y) + k*ln(2)
        // where y is in the range [1, 2)
        uint256 k = 0;
        uint256 y = x;

        // Scale y down to [PRECISION, 2*PRECISION)
        while (y >= 2 * PRECISION) {
            y = y / 2;
            k++;
        }

        // Calculate ln(y) using Taylor series for y-1 where y is close to 1
        // ln(y) = (y-1) - (y-1)^2/2 + (y-1)^3/3 - ...
        uint256 z = y - PRECISION;
        uint256 z_squared = (z * z) / PRECISION;

        // First few terms of the Taylor series
        uint256 result = z;
        result = result - (z_squared / 2);
        result = result + ((z * z_squared) / (3 * PRECISION));
        result =
            result -
            ((z_squared * z_squared) / (4 * PRECISION * PRECISION));

        // Add k*ln(2)
        uint256 ln2 = 693147180559945309417232121; // ln(2) * 10^27
        result = result + (k * ln2);

        return result;
    }

    function calculateGrowthRate(
        uint256 targetPrice,
        uint256 maxSupply
    ) internal pure returns (uint256) {
        require(targetPrice > 0, "Target price must be greater than 0");
        require(maxSupply > 0, "Max supply must be greater than 0");

        // Calculate ln(targetPrice)
        uint256 targetPriceScaled = (targetPrice * PRECISION) / (10 ** 18); // Scale to PRECISION
        uint256 lnTargetPrice = ln(targetPriceScaled);

        // Calculate ln(targetPrice)/maxSupply
        uint256 growthRate = (lnTargetPrice * PRECISION) / maxSupply;

        return growthRate;
    }
}
//TODO
// important : bonding curve price
// FEE TU BONDING SEND TO STAKING
