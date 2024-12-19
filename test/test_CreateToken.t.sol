// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/TokenFactory.sol";
import "../src/Token.sol";
import "../src/BondingCurve.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock contracts
contract MockWETH {
    function deposit() external payable {}
    function transfer(address, uint256) external pure returns (bool) { return true; }
    function approve(address, uint256) external pure returns (bool) { return true; }
}

contract MockUniswapV2Factory {
    address public pair;

    function createPair(address, address) external returns (address) {
        pair = address(new MockPair());
        return pair;
    }

    function getPair(address, address) external view returns (address) {
        return pair;
    }
}

contract MockPair {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    // This should be called by Router after adding liquidity
    function mint(address to) external returns (uint256 liquidity) {
        liquidity = 100 ether;
        _mint(to, liquidity);
        return liquidity;
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] = amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "INSUFFICIENT_BALANCE");
        
        balanceOf[msg.sender] -= value;
        
        if (to != address(0)) {
            balanceOf[to] += value;
        } else {
            totalSupply -= value;
        }
        
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }
}

contract MockUniswapV2Router {
    address public immutable WETH;
    address public factory;
    MockUniswapV2Factory private factoryContract;

    constructor(address _WETH, address _factory) {
        WETH = _WETH;
        factory = _factory;
        factoryContract = MockUniswapV2Factory(_factory);
    }

    function addLiquidityETH(
        address,
        uint256 amountTokenDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // Get the pair and mint LP tokens to the user
        address pair = factoryContract.getPair(address(0), address(0));
        liquidity = MockPair(pair).mint(to);
        
        return (amountTokenDesired, msg.value, liquidity);
    }
}

contract TokenFactoryTest is Test {
    TokenFactory public factory;
    Token public tokenImplementation;
    BondingCurve public bondingCurve;
    address public user1 = address(0x1);
    uint256 public constant FEE_PERCENT = 500; // 5%
    uint256 public constant SLOPE = 1e18; // 1.0
    uint256 public constant INITIAL_PRICE = 1e17; // 0.1

    function setUp() public {
        // Deploy implementation contracts
        tokenImplementation = new Token();
        bondingCurve = new BondingCurve(SLOPE, INITIAL_PRICE);
        
        // Deploy mocks
        MockWETH weth = new MockWETH();
        MockUniswapV2Factory uniswapFactory = new MockUniswapV2Factory();
        MockUniswapV2Router uniswapRouter = new MockUniswapV2Router(
            address(weth),
            address(uniswapFactory)
        );
        
        // Deploy factory
        factory = new TokenFactory(
            address(tokenImplementation),
            address(uniswapRouter),
            address(uniswapFactory),
            address(bondingCurve),
            FEE_PERCENT
        );

        // Setup user with ETH
        vm.deal(user1, 100 ether);
    }

    function test_CreateTokenAndAddLiquidity() public {
        vm.startPrank(user1);

        // Create token
        address tokenAddress = factory.createToken("Test Token", "TEST");
        Token token = Token(tokenAddress);
        
        // Verify initial state
        assertEq(uint256(factory.tokens(tokenAddress)), uint256(TokenFactory.TokenState.FUNDING));
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.totalSupply(), 0);

        // Calculate required ETH including fee
        uint256 fundingGoal = factory.FUNDING_GOAL();
        uint256 feeAmount = (fundingGoal * FEE_PERCENT) / factory.FEE_DENOMINATOR();
        uint256 totalRequired = fundingGoal + feeAmount;

        // Buy tokens to reach funding goal
        factory.buy{value: totalRequired}(tokenAddress);

        // Verify final state
        assertEq(uint256(factory.tokens(tokenAddress)), uint256(TokenFactory.TokenState.TRADING));
        assertEq(factory.collateral(tokenAddress), 0); // All collateral should be used for liquidity
        
        // Verify liquidity pool exists
        address pair = MockUniswapV2Factory(factory.uniswapV2Factory()).getPair(tokenAddress, factory.uniswapV2Router());
        assertTrue(pair != address(0), "Liquidity pool not created");
        
        // Verify initial supply was minted and split correctly
        uint256 expectedTotalSupply = factory.INITIAL_SUPPLY() + 
            bondingCurve.getAmountOut(0, fundingGoal);
        assertEq(token.totalSupply(), expectedTotalSupply);

        // Verify fees were collected
        assertEq(factory.fee(), feeAmount);

        vm.stopPrank();
    }
}