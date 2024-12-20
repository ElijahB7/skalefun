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
    address public owner;
    
    // Test addresses for UniswapV2
    address constant UNISWAP_V2_ROUTER = address(0x1);
    address constant UNISWAP_V2_FACTORY = address(0x2);
    
    function setUp() public {
        // Set owner
        owner = address(this);
        
        // Deploy token implementation
        tokenImplementation = new Token();
        
        // Deploy bonding curve with required parameters
        bondingCurve = new BondingCurve(
            1000, // initial price
            2000  // price increment
        );
        
        // Deploy factory
        factory = new TokenFactory(
            address(tokenImplementation),
            UNISWAP_V2_ROUTER,
            UNISWAP_V2_FACTORY,
            address(bondingCurve),
            100 // 1% fee
        );
    }
    
    function testCreateToken() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        string memory ipfsHash = "QmTest123";
        string memory description = "Test token description";
        
        // Create token with all required parameters
        address tokenAddress = factory.createToken(
            name, 
            symbol,
            ipfsHash,
            description
        );
        
        // Assert token was created
        assertTrue(tokenAddress != address(0), "Token address should not be zero");
        
        // Get the token instance
        Token token = Token(tokenAddress);
        
        // Verify token details
        assertEq(token.name(), name, "Token name should match");
        assertEq(token.symbol(), symbol, "Token symbol should match");
        
        // Verify metadata
        (string memory storedHash, string memory storedDesc) = token.getMetadata();
        assertEq(storedHash, ipfsHash, "IPFS hash should match");
        assertEq(storedDesc, description, "Description should match");
        
        // Verify token state in factory
        assertEq(uint256(factory.tokens(tokenAddress)), uint256(TokenFactory.TokenState.FUNDING), "Token should be in FUNDING state");
    }
}