// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/TokenFactory.sol";
import "../src/Token.sol";
import "../src/BondingCurve.sol";

// Updated MaliciousReceiver contract
    contract MaliciousReceiver {
        TokenFactory public factory;
        uint256 public attackCount;
    
        constructor(address _factory) {
            factory = TokenFactory(_factory);
        }
    
        // This will be called when receiving ETH
        receive() external payable {
            if(attackCount < 5) {
                attackCount++;
                // Try to reenter during the ETH receive
                factory.sell(msg.sender, 100);
            }
        }
    
        function attackSell(address token) external {
            // Initial sell to trigger receive()
            uint256 amount = Token(token).balanceOf(address(this));
            factory.sell(token, amount);
        }
    }

contract TokenFactoryTest is Test {

    TokenFactory public factory;
    Token public tokenImplementation;
    BondingCurve public bondingCurve;
    address public constant UNISWAP_ROUTER = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant UNISWAP_FACTORY = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    
    address public user1;
    address public user2;

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy implementation contracts
        tokenImplementation = new Token();
        bondingCurve = new BondingCurve(1 ether, 2 ether); // Example parameters
        
        // Deploy factory
        factory = new TokenFactory(
            address(tokenImplementation),
            UNISWAP_ROUTER,
            UNISWAP_FACTORY,
            address(bondingCurve),
            100 // 1% fee
        );

        // Setup users with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

   function testSellFunctionReentrancyRisk() public {

        // Deploy malicious receiver contract
        MaliciousReceiver attacker = new MaliciousReceiver(address(factory));
        vm.deal(address(attacker), 10 ether);

        // Create token
        vm.prank(address(attacker));
        address tokenAddress = factory.createToken("Attack Token", "ATK");

        // First do a successful buy
        vm.startPrank(address(attacker));
        factory.buy{value: 1 ether}(tokenAddress);
        vm.stopPrank();

        // Get the token balance
        Token token = Token(tokenAddress);
        uint256 attackerBalance = token.balanceOf(address(attacker));

        // Approve tokens to be spent by factory
        vm.prank(address(attacker));
        token.approve(address(factory), attackerBalance);

        // Now test the reentrancy in sell
        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.prank(address(attacker));
    
        // Attempt the attack
        attacker.attackSell(tokenAddress);
    }
}