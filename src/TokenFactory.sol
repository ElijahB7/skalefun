// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {Clones} from "lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {BondingCurve} from "./BondingCurve.sol";
import {Token} from "./Token.sol";

contract TokenFactory is ReentrancyGuard, Ownable {

    struct TokenData {
        TokenState state;
        uint256 collateral;
        uint256 lastTotalSupply;  
    }

    enum TokenState {
        NOT_CREATED,
        FUNDING,
        TRADING
    }

    uint256 public constant MAX_SUPPLY = 10 ** 9 * 1 ether; // 1 Billion
    uint256 public constant INITIAL_SUPPLY = (MAX_SUPPLY * 1) / 5;
    uint256 public constant FUNDING_SUPPLY = (MAX_SUPPLY * 4) / 5;
    uint256 public constant FUNDING_GOAL = 20 ether;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 private constant PRECISION_SCALE = 1e18;
    uint256 public constant MAX_FEE_PERCENT = 1000; // 10%

    mapping(address => TokenState) public tokens;
    mapping(address => uint256) public collateral;
    mapping(address => TokenData) internal tokenData;
    address public immutable tokenImplementation;
    address public uniswapV2Router;
    address public uniswapV2Factory;
    BondingCurve public bondingCurve;
    uint256 public feePercent; // bp
    uint256 public fee;
    bool public paused;

    // Events
    event TokenCreated(address indexed token, uint256 timestamp);
    event TokenLiqudityAdded(address indexed token, uint256 timestamp);
    event TokenSold(address indexed token, address indexed seller, uint256 amount, uint256 ethReceived, uint256 feeAmount);
    event BondingCurveUpdated(address indexed newBondingCurve);
    event FeePercentChanged(uint256 newFeePercent);
    event PausedSet(bool isPaused);
    event FeesClaimed(address indexed owner, uint256 amount);

    // Errors
    error TokenNotFunding();
    error ZeroAmount();
    error ETHTransferFailed();
    error InsufficientCollateral();

    
    constructor(
        address _tokenImplementation,
        address _uniswapV2Router,
        address _uniswapV2Factory,
        address _bondingCurve,
        uint256 _feePercent
    ) Ownable(msg.sender) {
        require(_tokenImplementation != address(0), "Zero address");
        require(_uniswapV2Router != address(0), "Zero address");
        require(_uniswapV2Factory != address(0), "Zero address");
        require(_bondingCurve != address(0), "Zero address");
        require(_feePercent <= MAX_FEE_PERCENT, "Fee too high");
    
        tokenImplementation = _tokenImplementation;
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Factory = _uniswapV2Factory;
        bondingCurve = BondingCurve(_bondingCurve);
        feePercent = _feePercent;
    }

    // Admin functions

    function setBondingCurve(address _bondingCurve) external onlyOwner {
        require(_bondingCurve != address(0), "Zero address");
        bondingCurve = BondingCurve(_bondingCurve);
        emit BondingCurveUpdated(_bondingCurve);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= MAX_FEE_PERCENT, "Fee too high");
        feePercent = _feePercent;
        emit FeePercentChanged(_feePercent);
    }

    function claimFee() external onlyOwner {
        uint256 amountToTransfer = fee;
        fee = 0; // Update state before transfer
        (bool success,) = msg.sender.call{value: amountToTransfer}(new bytes(0));
        require(success, "ETH send failed");
        emit FeesClaimed(msg.sender, amountToTransfer);
    }

    // Token functions

   function createToken(
    string memory name, 
    string memory symbol,
    string memory ipfsHash,
    string memory description
) external whenNotPaused returns (address) {
    require(bytes(name).length > 0 && bytes(name).length <= 32, "Invalid name length");
    require(bytes(symbol).length > 0 && bytes(symbol).length <= 8, "Invalid symbol length");
    require(bytes(ipfsHash).length > 0, "IPFS hash required");
    require(bytes(description).length > 0, "Description required");

    address tokenAddress = Clones.clone(tokenImplementation);
    Token token = Token(tokenAddress);
    token.initialize(name, symbol, ipfsHash, description);
    
    // Don't mint everything initially - tokens will be minted as needed during buy()
    tokens[tokenAddress] = TokenState.FUNDING;
    emit TokenCreated(tokenAddress, block.timestamp);
    return tokenAddress;
}

    function buy(address tokenAddress) external whenNotPaused payable nonReentrant {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not found");
        require(msg.value > 0, "ETH not enough");

        Token token = Token(tokenAddress);
        uint256 currentSupply = token.totalSupply(); // Remove tokenAddress argument
        
        // Calculate fee
        uint256 contributionWithoutFee = (msg.value * FEE_DENOMINATOR) / (FEE_DENOMINATOR + feePercent);
        uint256 feeAmount = msg.value - contributionWithoutFee;
        fee += feeAmount;

        // Calculate tokens out
        uint256 tokensOut = bondingCurve.getAmountOut(tokenAddress, contributionWithoutFee); // Pass tokenAddress instead of currentSupply
        require(tokensOut > 0, "No tokens returned");
        require(currentSupply + tokensOut <= FUNDING_SUPPLY, "Exceeds max supply");

        // Rest of the function remains the same
        uint256 currentCollateral = collateral[tokenAddress];
        uint256 newCollateral = currentCollateral + contributionWithoutFee;
        collateral[tokenAddress] = newCollateral;

        token.mint(msg.sender, tokensOut);
        
        if (newCollateral >= FUNDING_GOAL) {
            token.mint(address(this), INITIAL_SUPPLY);
            address pair = createLiquilityPool(tokenAddress);
            uint256 liquidity = addLiquidity(tokenAddress, INITIAL_SUPPLY, newCollateral);
            burnLiquidityToken(pair, liquidity);
            collateral[tokenAddress] = 0;
            tokens[tokenAddress] = TokenState.TRADING;
            emit TokenLiqudityAdded(tokenAddress, block.timestamp);
        }
    }

    function sell(address tokenAddress, uint256 amount) external nonReentrant whenNotPaused returns (uint256 ethReceived) {
        // Cache storage reads in a single operation
        TokenState currentState = tokens[tokenAddress];
        if (currentState != TokenState.FUNDING) revert TokenNotFunding();
        if (amount == 0) revert ZeroAmount();
    
        // Cache storage values
        uint256 currentCollateral = collateral[tokenAddress];
        Token token = Token(tokenAddress);
    
        // Perform calculations in unchecked block since we have validations
        uint256 rawETHAmount;
        uint256 feeAmount;
        unchecked {
            // Get ETH amount and calculate fees
            rawETHAmount = bondingCurve.getFundsReceived(token.totalSupply(), amount);
            feeAmount = (rawETHAmount * feePercent) / FEE_DENOMINATOR;
            ethReceived = rawETHAmount - feeAmount;
        }
    
        // Validate collateral
        if (currentCollateral < rawETHAmount) revert InsufficientCollateral();
    
        // Execute state changes before external calls (CEI pattern)
        token.burn(msg.sender, amount);
    
        unchecked {
            // Update state variables
            collateral[tokenAddress] = currentCollateral - rawETHAmount;
            fee += feeAmount;
        }

        // Perform ETH transfer last
        (bool success,) = msg.sender.call{value: ethReceived}("");
        if (!success) revert ETHTransferFailed();
    
        emit TokenSold(tokenAddress, msg.sender, amount, ethReceived, feeAmount);
    }

    // Internal functions

    function createLiquilityPool(address tokenAddress) internal returns (address) {
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapV2Factory);
        IUniswapV2Router01 router = IUniswapV2Router01(uniswapV2Router);

        address pair = factory.createPair(tokenAddress, router.WETH());
        return pair;
    }

    function addLiquidity(address tokenAddress, uint256 tokenAmount, uint256 ethAmount) internal returns (uint256) {
        Token token = Token(tokenAddress);
        IUniswapV2Router01 router = IUniswapV2Router01(uniswapV2Router);
        token.approve(uniswapV2Router, tokenAmount);
    
        uint256 minTokenAmount = tokenAmount * 95 / 100; // 5% slippage
        uint256 minEthAmount = ethAmount * 95 / 100;
    
        (,, uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            tokenAddress, 
            tokenAmount, 
            minTokenAmount, 
            minEthAmount, 
            address(this), 
            block.timestamp + 300 // 5 minute deadline
        );
    
        // Reset approval
        token.approve(uniswapV2Router, 0);
        return liquidity;
    }

    function burnLiquidityToken(address pair, uint256 liquidity) internal {
        SafeERC20.safeTransfer(IERC20(pair), address(0), liquidity);
    }

    function calculateFee(uint256 _amount, uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent + FEE_DENOMINATOR / 2) / FEE_DENOMINATOR;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }
}
