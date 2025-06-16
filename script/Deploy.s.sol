// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BitLuck} from "../src/BitLuck.sol";
import {MockUSDT} from "../src/MockUSDT.sol";

contract DeployScript is Script {
    // BSC Testnet addresses
    address constant PANCAKE_ROUTER_TESTNET =
        0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
    address constant USDT_TESTNET = 0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock USDT for testing (in production, use real USDT address)
        MockUSDT usdt = new MockUSDT();
        console.log("Mock USDT deployed to:", address(usdt));

        // Deploy BitLuck
        BitLuck bitluck = new BitLuck(address(usdt), PANCAKE_ROUTER_TESTNET);
        console.log("BitLuck deployed to:", address(bitluck));

        // Provide some USDT to BitLuck contract for testing rewards
        usdt.mint(address(bitluck), 100000 * 10 ** 18); // 100k USDT
        console.log("Minted 100k USDT to BitLuck contract");

        console.log("Total BTL Supply:", bitluck.totalSupply());
        console.log("Owner:", bitluck.owner());
        console.log(
            "Trading Status (0 = not started):",
            bitluck.startTradeBlock()
        );

        vm.stopBroadcast();
    }

    function deployWithRealUSDT() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy BitLuck with real USDT
        BitLuck bitluck = new BitLuck(USDT_TESTNET, PANCAKE_ROUTER_TESTNET);
        console.log("BitLuck deployed to:", address(bitluck));
        console.log("Using real USDT at:", USDT_TESTNET);
        console.log("Using PancakeSwap router at:", PANCAKE_ROUTER_TESTNET);

        vm.stopBroadcast();
    }

    function deployAndConfigure() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        MockUSDT usdt = new MockUSDT();
        BitLuck bitluck = new BitLuck(address(usdt), PANCAKE_ROUTER_TESTNET);

        // Configure for testing
        usdt.mint(address(bitluck), 100000 * 10 ** 18);

        // Open trading
        bitluck.openTrading();

        console.log("Deployment and configuration complete:");
        console.log("Mock USDT:", address(usdt));
        console.log("BitLuck:", address(bitluck));
        console.log("Trading started at block:", bitluck.startTradeBlock());

        vm.stopBroadcast();
    }
}
