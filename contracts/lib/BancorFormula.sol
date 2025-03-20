pragma solidity ^0.8.20;

import "./SafeMath.sol";

import "./Power.sol"; // Efficient power function.

contract BancorFormula is Power {
    using SafeMath for uint256;
    uint32 private constant MAX_RESERVE_RATIO = 1000000;

    /**
     * @notice Calculates the number of tokens that will be minted for a given deposit amount
     * @dev Optimized for handling large amounts (e.g., 24 ETH) with improved precision
     * @param _supply Current token supply
     * @param _reserveBalance Current reserve balance
     * @param _reserveRatio Reserve ratio, represented in ppm (1-1000000)
     * @param _depositAmount Amount of reserve tokens to deposit
     * @return Amount of tokens that will be minted
     */
    function calculatePurchaseReturn(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveRatio,
        uint256 _depositAmount
    ) public view returns (uint256) {
        // validate input
        require(
            _supply > 0 &&
                _reserveBalance > 0 &&
                _reserveRatio > 0 &&
                _reserveRatio <= MAX_RESERVE_RATIO,
            "Invalid parameters"
        );

        // special case for 0 deposit amount
        if (_depositAmount == 0) {
            return 0;
        }

        // Check for potential overflow in baseN calculation
        require(
            _depositAmount <= type(uint256).max - _reserveBalance,
            "Deposit amount too large"
        );

        // special case if the ratio = 100%
        if (_reserveRatio == MAX_RESERVE_RATIO) {
            return _supply.mul(_depositAmount).div(_reserveBalance);
        }

        uint256 result;
        uint8 precision;

        // Calculate new reserve balance after deposit
        uint256 baseN = _depositAmount.add(_reserveBalance);

        // Calculate the result using the power function with increased precision
        (result, precision) = power(
            baseN,
            _reserveBalance,
            _reserveRatio,
            MAX_RESERVE_RATIO
        );

        // Calculate new token supply with safe math operations
        uint256 newTokenSupply = _supply.mul(result) >> precision;

        // Ensure the calculation doesn't underflow
        require(newTokenSupply >= _supply, "Calculation underflow");

        return newTokenSupply - _supply;
    }

    function calculateSaleReturn(
        uint256 _supply,
        uint256 _reserveBalance,
        uint32 _reserveRatio,
        uint256 _sellAmount
    ) public view returns (uint256) {
        // validate input
        require(
            _supply > 0 &&
                _reserveBalance > 0 &&
                _reserveRatio > 0 &&
                _reserveRatio <= MAX_RESERVE_RATIO &&
                _sellAmount <= _supply
        );
        // special case for 0 sell amount
        if (_sellAmount == 0) {
            return 0;
        }
        // special case for selling the entire supply
        if (_sellAmount == _supply) {
            return _reserveBalance;
        }
        // special case if the ratio = 100%
        if (_reserveRatio == MAX_RESERVE_RATIO) {
            return _reserveBalance.mul(_sellAmount).div(_supply);
        }
        uint256 result;
        uint8 precision;
        uint256 baseD = _supply - _sellAmount;
        (result, precision) = power(
            _supply,
            baseD,
            MAX_RESERVE_RATIO,
            _reserveRatio
        );
        uint256 oldBalance = _reserveBalance.mul(result);
        uint256 newBalance = _reserveBalance << precision;
        return oldBalance.sub(newBalance).div(result);
    }
}
