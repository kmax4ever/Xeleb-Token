// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./AiAgentToken.sol";
import "hardhat/console.sol";
import "./lib/BancorFormula.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
contract BondingCurve is BancorFormula, Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeMath for uint256;
    AiAgentToken public agentToken;

    IUniswapV2Router01 public immutable pancakeSwapRouter;

    // Bonding curve parameters
    uint256 public constant INITIAL_PRICE = 765e7; // 0.00000000765 ETH initial price
    uint256 public MAX_SUPPLY; // 700M tokens

    // Trading fees
    uint256 public constant BURN_PERCENT = 100; // 1%
    // max buy percent
    uint256 public MAX_BUY_PERCENT = 1000;
    uint256 public DENOMINATOR = 10000;
    uint256 private MAX_BUY_AMOUNT;
    // Trading limits
    uint256 public constant MAX_SELL_AMOUNT = 1000000000 * 1e18; //  tokens

    // lock , vesting config
    uint256 public constant BUY_UNLOCK_PERCENT = 1000; // 1%
    uint256 public constant VESTING_PERCENT = 9000; //0.1%

    // Time-based restrictions
    uint256 public constant TRADE_COOLDOWN = 0;
    mapping(address => uint256) public lastTradeTime;
    uint256 public totalSoldAmount = 0;
    uint256 public totalRaisedAmount = 0;
    // Treasury
    uint256 public constant BONDING_TARGET = 24e18;

    uint32 public reserveRatio = 655000;

    bool public isRunBonding = true;

    address public constant PANCAKE_SWAP_ROUTER_V2 =
        0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

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

    event LiquidityAdded(
        address indexed provider,
        uint256 tokenAmount,
        uint256 ethAmount,
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
        MAX_BUY_AMOUNT = (initSupply * MAX_BUY_PERCENT) / DENOMINATOR;
        pancakeSwapRouter = IUniswapV2Router01(PANCAKE_SWAP_ROUTER_V2);
    }

    // Buy tokens with ETH
    function buyTokens() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        if (totalRaisedAmount >= BONDING_TARGET) {
            //TODO handle add liquid
        }

        require(isRunBonding, "Bonding stop!");

        // require(address(this).balance <= BONDING_TARGET, "Completed bonding!");
        require(
            block.timestamp >= lastTradeTime[msg.sender] + TRADE_COOLDOWN,
            "Too soon"
        );

        uint256 tokenAmount = getTokensForETH(msg.value);

        require(tokenAmount > 0, "buyTokens Err: Invalid token amount!");
        console.log("buyTokens xxx");
        require(
            totalSoldAmount + tokenAmount <= MAX_SUPPLY,
            "Exceeds available supply"
        );
        // stop bonding
        if (
            totalSoldAmount + tokenAmount == MAX_SUPPLY ||
            totalRaisedAmount + msg.value >= BONDING_TARGET
        ) {
            isRunBonding = false;
        }

        uint256 burnAmount = (tokenAmount * BURN_PERCENT) / DENOMINATOR;
        uint256 remainingAmount = tokenAmount - burnAmount;
        // Create vesting schedule
        agentToken.createVestingScheduleForBuyer(msg.sender, remainingAmount);

        totalSoldAmount += tokenAmount;
        totalRaisedAmount += msg.value;
        agentToken.burn(msg.sender, burnAmount);

        lastTradeTime[msg.sender] = block.timestamp;
        emit TokensPurchased(
            msg.sender,
            msg.value,
            tokenAmount,
            block.timestamp
        );
        uint256 currentPrice = msg.value / tokenAmount;
        emit Trade(msg.sender, tokenAmount, currentPrice, block.timestamp);
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
            totalRaisedAmount >= refundAmount,
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
        totalRaisedAmount -= refundAmount;

        uint256 currentPrice = refundAmount / tokenAmount;
        emit TokensSold(msg.sender, tokenAmount, refundAmount, block.timestamp);
        emit Trade(msg.sender, tokenAmount, currentPrice, block.timestamp);
    }

    function getTokensForETH(uint256 _ethAmount) public view returns (uint256) {
        uint256 tokenAmount;
        if (totalSoldAmount == 0) {
            tokenAmount = _ethAmount * INITIAL_PRICE;
            if (tokenAmount > MAX_BUY_AMOUNT) {
                return MAX_BUY_AMOUNT;
            }
        } else {
            tokenAmount = calculatePurchaseReturn(
                totalSoldAmount,
                totalRaisedAmount,
                uint32(reserveRatio),
                _ethAmount
            );
            // for sure not over MAX_SUPPLY
        }

        if (totalSoldAmount + tokenAmount > MAX_SUPPLY) {
            tokenAmount = MAX_SUPPLY - totalSoldAmount;
        }
        return tokenAmount;
    }

    function getETHForTokens(
        uint256 tokenAmount
    ) public view returns (uint256) {
        uint256 ethAmount;
        if (totalSoldAmount == 0) {
            return 0;
        }
        ethAmount = calculateSaleReturn(
            totalSoldAmount,
            totalRaisedAmount,
            uint32(reserveRatio),
            tokenAmount
        );
        // for sure not over balance
        if (totalRaisedAmount < ethAmount) {
            ethAmount = totalSoldAmount;
        }
        return ethAmount;
    }

    // Emergency functions
    receive() external payable {}
    fallback() external payable {}

    function getRaisedAmount() public view returns (uint256) {
        return totalRaisedAmount;
    }
    function getTotalSoldAmount() public view returns (uint256) {
        return totalSoldAmount;
    }

    function getCurrentPrice() public view returns (uint256) {
        uint256 ethAmount = 1e10;
        uint256 tokenAmount = getTokensForETH(ethAmount);
        if (tokenAmount == 0) {
            return 0;
        }
        return (ethAmount * 1e18) / tokenAmount;
    }

    function creatorBuy(
        address buyer,
        uint256 ethValue,
        uint256 tokenAmount
    ) external onlyOwner {
        totalSoldAmount += tokenAmount;
        totalRaisedAmount += ethValue;
        emit TokensPurchased(buyer, ethValue, tokenAmount, block.timestamp);
        emit Trade(buyer, tokenAmount, ethValue / tokenAmount, block.timestamp);
    }

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
//TODO
// FEE OF BONDING SEND TO STAKING
