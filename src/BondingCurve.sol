// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {Token} from "./Token.sol";

contract BondingCurve {
    using FixedPointMathLib for uint256;

    uint256 public immutable INITIAL_PRICE;
    uint256 public immutable MULTIPLIER;
    uint256 public constant FUNDING_SUPPLY = 800_000_000 * 1e18; // 800M tokens

    constructor() {
         // Start at 0.0000000045 ETH (4.5 gwei)
        INITIAL_PRICE = 4_500_000_000;
        // This multiplier gives us a ~10x increase over 800M tokens
        MULTIPLIER = 50;
    }

    function getCurrentPrice(uint256 currentSupply) public view returns (uint256) {
        // Base price + linear increase based on current supply
        // Price should go from 0.00028 ETH to 0.0028 ETH over FUNDING_SUPPLY
        return INITIAL_PRICE + ((currentSupply * MULTIPLIER) / 1 ether);
    }

    function getAmountOut(address tokenAddress, uint256 ethIn) public view returns (uint256) {
    Token token = Token(tokenAddress);
    uint256 currentSupply = token.totalSupply();
    uint256 currentPrice = getCurrentPrice(currentSupply);  // Use the existing getCurrentPrice function
    require(currentPrice > 0, "Invalid price");
    
    // Calculate tokens out, maintaining wei precision
    return (ethIn * 1 ether) / currentPrice;
}

    function getFundsReceived(uint256 currentSupply, uint256 tokenAmount) public view returns (uint256) {
        require(currentSupply >= tokenAmount, "Invalid amount");
        uint256 currentPrice = getCurrentPrice(currentSupply);
        return (tokenAmount * currentPrice) / 1 ether;
    }
}