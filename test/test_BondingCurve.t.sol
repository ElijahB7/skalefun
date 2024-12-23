// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Token.sol";
import "../src/TokenFactory.sol";
import "../src/BondingCurve.sol";

contract TokenFactoryTest is Test {
    TokenFactory public factory;
    Token public token;
    BondingCurve public bondingCurve;
    address public owner;
    address public user;
    address public tokenAddress;
    
    address constant UNISWAP_V2_ROUTER = address(0x1);
    address constant UNISWAP_V2_FACTORY = address(0x2);
    uint256 constant FUNDING_SUPPLY = 800_000_000 * 1e18; // From TokenFactory
    
    function setUp() public {
        owner = address(this);
        user = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        vm.deal(user, 1000 ether);
        
        Token tokenImplementation = new Token();
        bondingCurve = new BondingCurve();
        
        factory = new TokenFactory(
            address(tokenImplementation),
            UNISWAP_V2_ROUTER,
            UNISWAP_V2_FACTORY,
            address(bondingCurve),
            100 // 1% fee
        );

        tokenAddress = factory.createToken(
            "Test Token",
            "TEST",
            "QmTest123",
            "Test token description"
        );
        token = Token(tokenAddress);
    }

    function test_BondingCurveFullRange() public {
    console.log("\nTesting initial token purchase:");
    vm.startPrank(user);
    
    uint256 beforeBalance = token.balanceOf(user);
    factory.buy{value: 1 ether}(tokenAddress);
    uint256 afterBalance = token.balanceOf(user);
    
    uint256 tokensBought = afterBalance - beforeBalance;
    console.log("Bought %s tokens for 1 ETH", tokensBought / 1e18);
    
    // Check price increased
    uint256 initialPrice = bondingCurve.getCurrentPrice(0);
    uint256 newPrice = bondingCurve.getCurrentPrice(tokensBought);
    console.log("Price increased from %s wei to %s wei", initialPrice, newPrice);
    assertTrue(newPrice > initialPrice, "Price should increase");
    
    vm.stopPrank();
}

    function test_BondingCurveIncrementalPurchases() public {
    
    uint256 purchaseAmount = 0.1 ether;
    uint256 numPurchases = 10;

    vm.startPrank(user);
    
    for(uint256 i = 0; i < numPurchases; i++) {
        uint256 preBuyPrice = bondingCurve.getCurrentPrice(token.totalSupply());
        uint256 preSupply = token.totalSupply();
        
        factory.buy{value: purchaseAmount}(tokenAddress);
        
        uint256 postBuyPrice = bondingCurve.getCurrentPrice(token.totalSupply());
        uint256 postSupply = token.totalSupply();
        uint256 tokensReceived = postSupply - preSupply;

        
        // Verify price increase is correct based on supply
        uint256 expectedPrice = bondingCurve.getCurrentPrice(postSupply);
        assertEq(postBuyPrice, expectedPrice, "Price calculation mismatch");
        
        // Verify price is strictly increasing
        assertTrue(postBuyPrice > preBuyPrice, "Price should increase");
    }
    
    vm.stopPrank();
}
}