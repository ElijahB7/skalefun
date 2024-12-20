// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/TokenFactory.sol";
import "../src/BondingCurve.sol";

contract TokenFactoryTest is Test {
    TokenFactory public factory;
    Token public tokenImplementation;
    BondingCurve public bondingCurve;
    Token public token;
    address public owner;
    address public buyer;
    
    // Test addresses for UniswapV2
    address constant UNISWAP_V2_ROUTER = address(0x1);
    address constant UNISWAP_V2_FACTORY = address(0x2);
    
    function setUp() public {
        // Set owner and buyer
        owner = address(this);
        buyer = makeAddr("buyer");
        vm.deal(buyer, 10000 ether);
        
        // Deploy contracts
        tokenImplementation = new Token();
        
        // Use much smaller numbers for the bonding curve parameters
        bondingCurve = new BondingCurve(
            1 ether, // 1 ETH initial price
            0.1 ether // 0.1 ETH price increment
        );
        
        factory = new TokenFactory(
            address(tokenImplementation),
            UNISWAP_V2_ROUTER,
            UNISWAP_V2_FACTORY,
            address(bondingCurve),
            100 // 1% fee
        );

        // Create a test token
        address tokenAddress = factory.createToken(
            "Test Token",
            "TEST",
            "QmTest123",
            "Test token description"
        );
        token = Token(tokenAddress);
    }
    
    function testBuyAndSellDuringFunding() public {
        uint256 buyAmount = 1 ether;
        
        vm.startPrank(buyer);
        
        // Buy tokens
        factory.buy{value: buyAmount}(address(token));
        
        // Check buyer's token balance
        uint256 buyerBalance = token.balanceOf(buyer);
        assertTrue(buyerBalance > 0, "Buyer should have tokens");
        
        // Sell half the tokens
        uint256 sellAmount = buyerBalance / 2;
        uint256 ethBalanceBefore = buyer.balance;
        
        token.approve(address(factory), sellAmount);
        uint256 ethReceived = factory.sell(address(token), sellAmount);
        
        // Verify sale results
        assertEq(token.balanceOf(buyer), buyerBalance - sellAmount, "Incorrect token balance after sell");
        assertEq(buyer.balance, ethBalanceBefore + ethReceived, "Incorrect ETH balance after sell");
        
        vm.stopPrank();
    }
    
    function testMultipleBuyers() public {
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 100 ether);
        
        uint256 buyAmount = 5 ether;
        
        // First buyer
        vm.prank(buyer);
        factory.buy{value: buyAmount}(address(token));
        uint256 buyer1Balance = token.balanceOf(buyer);
        
        // Second buyer
        vm.prank(buyer2);
        factory.buy{value: buyAmount}(address(token));
        uint256 buyer2Balance = token.balanceOf(buyer2);
        
        // Verify balances
        assertTrue(buyer1Balance > 0, "Buyer 1 should have tokens");
        assertTrue(buyer2Balance > 0, "Buyer 2 should have tokens");
        assertTrue(buyer2Balance < buyer1Balance, "Second buyer should get fewer tokens due to bonding curve");
    }
    
    function testBuyWithInsufficientETH() public {
        vm.prank(buyer);
        vm.expectRevert("ETH not enough");
        factory.buy{value: 0}(address(token));
    }
}