// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "hardhat/console.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "./lib/SafeMath.sol";

import "./lib/BancorFormula.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BondingTestBarcon is ReentrancyGuard {
    using SafeMath for uint256;
    uint256 private constant _exponent = 2;

    uint256 private _loss_fee_percentage;

    uint256 private supplyCap;

    event tokensBought(
        address indexed buyer,
        uint amount,
        uint total_supply,
        uint newPrice
    );
    event tokensSold(
        address indexed seller,
        uint amount,
        uint total_supply,
        uint newPrice
    );
    event withdrawn(address from, address to, uint amount, uint time);
    uint256 public totalSoldAmount;
    uint256 public totalRaisedAmount;

    constructor() {
        supplyCap = 1000000;
        _loss_fee_percentage = 1000;
        supplyCap = 1000000000;
    }

    function buyTokens() external payable {}
}
