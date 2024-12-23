// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/TokenFactory.sol";
import "../src/Token.sol";
import "../src/BondingCurve.sol";

// Sepolia deployment

contract DeployTokenFactory is Script {
    // Sepolia addresses
    address constant UNISWAP_V2_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant UNISWAP_V2_FACTORY = 0x7E0987E5b3a30e3f2828572Bb659A548460a3003;
    uint256 constant FEE_PERCENT = 250; // 2.5% in basis points
    // Modified parameters
    uint256 constant BONDING_CURVE_A = 28000000000; // 0.000000028 ETH
    uint256 constant BONDING_CURVE_B = 2900000000; // pretty steep curve

    function run() external {
        vm.startBroadcast();
        // Deploy Token implementation
        Token tokenImplementation = new Token();
        console.log("Token implementation deployed to:", address(tokenImplementation));

        // Deploy BondingCurve
        BondingCurve bondingCurve = new BondingCurve(BONDING_CURVE_A, BONDING_CURVE_B);
        console.log("BondingCurve deployed to:", address(bondingCurve));

        // Deploy TokenFactory
        TokenFactory tokenFactory = new TokenFactory(
            address(tokenImplementation),
            UNISWAP_V2_ROUTER,
            UNISWAP_V2_FACTORY,
            address(bondingCurve),
            FEE_PERCENT
        );
        console.log("TokenFactory deployed to:", address(tokenFactory));

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\nDeployment Summary:");
        console.log("-------------------");
        console.log("Token Implementation:", address(tokenImplementation));
        console.log("BondingCurve:", address(bondingCurve));
        console.log("TokenFactory:", address(tokenFactory));
        console.log("Network:", block.chainid);
        console.log("Fee Percent:", FEE_PERCENT / 100, "%");
        console.log("\nUniswap V2 Addresses Used:");
        console.log("Router:", UNISWAP_V2_ROUTER);
        console.log("Factory:", UNISWAP_V2_FACTORY);
    }
}