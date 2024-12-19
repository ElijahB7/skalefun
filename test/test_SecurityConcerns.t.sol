// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./test_CreateToken.t.sol";  // Import our previous test helpers

contract TokenFactorySecurityTest is Test {
    TokenFactory public factory;
    Token public tokenImplementation;
    BondingCurve public bondingCurve;
    MockWETH public weth;
    MockUniswapV2Factory public uniswapFactory;
    MockUniswapV2Router public uniswapRouter;
    
    address public user1 = address(0x1);
    address public attacker = address(0x2);
    uint256 public constant FEE_PERCENT = 500; // 5%
    uint256 public constant SLOPE = 1e18;
    uint256 public constant INITIAL_PRICE = 1e17;

    function setUp() public {
        tokenImplementation = new Token();
        bondingCurve = new BondingCurve(SLOPE, INITIAL_PRICE);
        
        weth = new MockWETH();
        uniswapFactory = new MockUniswapV2Factory();
        uniswapRouter = new MockUniswapV2Router(
            address(weth),
            address(uniswapFactory)
        );
        
        factory = new TokenFactory(
            address(tokenImplementation),
            address(uniswapRouter),
            address(uniswapFactory),
            address(bondingCurve),
            FEE_PERCENT
        );

        vm.deal(user1, 1000 ether);
        vm.deal(attacker, 1000 ether);
    }

    function test_ReentrancyProtection() public {
        vm.startPrank(user1);
        
        // First create a token for the attacker
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(factory));
        address attackerTokenAddr = factory.createToken("Attack Token", "ATK");
        
        // Initialize attack state
        attacker.setToken(attackerTokenAddr);
        
        // Try to reenter during buy - should revert with nonReentrant error
        uint256 fundingGoal = factory.FUNDING_GOAL();
        uint256 feeAmount = (fundingGoal * FEE_PERCENT) / factory.FEE_DENOMINATOR();
        vm.expectRevert("ReentrancyGuard: reentrant call");
        factory.buy{value: fundingGoal + feeAmount}(address(attacker));
        
        vm.stopPrank();
    }

    function test_FeeManipulation() public {
        vm.startPrank(user1);
        address tokenAddress = factory.createToken("Test Token", "TEST");
        
        // Calculate initial ETH required with original fee
        uint256 fundingGoal = factory.FUNDING_GOAL();
        uint256 originalFee = factory.feePercent();
        uint256 originalFeeAmount = (fundingGoal * originalFee) / factory.FEE_DENOMINATOR();
        uint256 originalRequired = fundingGoal + originalFeeAmount;
        
        vm.stopPrank();
        
        // Owner changes fee right before user transaction
        vm.prank(factory.owner());
        factory.setFeePercent(1000); // 10%
        
        // User's transaction with old fee calculation should fail due to insufficient ETH
        vm.startPrank(user1);
        vm.expectRevert("ETH not enough");
        factory.buy{value: originalRequired}(tokenAddress);
        
        // Verify correct fee would work
        uint256 newFeeAmount = (fundingGoal * 1000) / factory.FEE_DENOMINATOR();
        factory.buy{value: fundingGoal + newFeeAmount}(tokenAddress);
        
        vm.stopPrank();
    }

    function test_FeeAccumulationLimit() public {
        vm.startPrank(user1);
        uint256 initialFee = factory.fee();
        
        // Create and fund one token
        address tokenAddress = factory.createToken("Test Token", "TEST");
        uint256 fundingGoal = factory.FUNDING_GOAL();
        uint256 feeAmount = (fundingGoal * FEE_PERCENT) / factory.FEE_DENOMINATOR();
        factory.buy{value: fundingGoal + feeAmount}(tokenAddress);
        
        // Verify fee increased correctly
        uint256 newFee = factory.fee();
        assertEq(newFee - initialFee, feeAmount, "Fee not accumulated correctly");
        assertLt(newFee, type(uint256).max - fundingGoal, "Fee too close to max");
        
        vm.stopPrank();
    }

    function test_MaxApprovalWindow() public {
        vm.startPrank(user1);
        address tokenAddress = factory.createToken("Test Token", "TEST");
        
        // Monitor approval events during buying process
        vm.recordLogs();
        uint256 fundingGoal = factory.FUNDING_GOAL();
        uint256 feeAmount = (fundingGoal * FEE_PERCENT) / factory.FEE_DENOMINATOR();
        factory.buy{value: fundingGoal + feeAmount}(tokenAddress);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundZeroApproval = false;
        
        // Verify approval is reset to zero after use
        for(uint i = 0; i < entries.length; i++) {
            if(entries[i].topics[0] == keccak256("Approval(address,address,uint256)")) {
                if(abi.decode(entries[i].data, (uint256)) == 0) {
                    foundZeroApproval = true;
                    break;
                }
            }
        }
        
        assertTrue(foundZeroApproval, "Approval not reset after use");
        vm.stopPrank();
    }
}

contract ReentrancyAttacker {
    TokenFactory private factory;
    bool private attacked;
    address public tokenAddress;
    
    constructor(address _factory) {
        factory = TokenFactory(_factory);
    }

    function setToken(address _tokenAddress) external {
        tokenAddress = _tokenAddress;
    }
    
    receive() external payable {
        if (!attacked && tokenAddress != address(0)) {
            attacked = true;
            // Try to reenter with a valid token address
            factory.buy{value: 1 ether}(tokenAddress);
        }
    }
}