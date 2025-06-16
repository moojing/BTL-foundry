// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BitLuck} from "../src/BitLuck.sol";
import {MockUSDT} from "../src/MockUSDT.sol";

contract DeployScript is Script {
    // BSC Testnet addresses - Official PancakeSwap V2
    address constant PANCAKE_ROUTER_V2_TESTNET =
        0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    /**
     * @dev USDT 作為 USD1 的部署代理地址
     *
     * 在測試網環境中，由於沒有 World Coin USD1 的官方合約，
     * 我們使用 USDT (0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684) 作為代理，
     * 以便測試 BitLuck 的完整功能。
     *
     * 主網部署時請替換為真實的 USD1 合約地址。
     */
    address constant USD1_TESTNET = 0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684; // Using USDT as USD1 proxy for testing

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock USDT for testing (in production, use real USDT address)
        MockUSDT usdt = new MockUSDT();
        console.log("Mock USDT deployed to:", address(usdt));

        // Deploy BitLuck
        BitLuck bitluck = new BitLuck(address(usdt), PANCAKE_ROUTER_V2_TESTNET);
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
        BitLuck bitluck = new BitLuck(USD1_TESTNET, PANCAKE_ROUTER_V2_TESTNET);
        console.log("BitLuck deployed to:", address(bitluck));
        console.log("Using real USDT at:", USD1_TESTNET);
        console.log("Using PancakeSwap router at:", PANCAKE_ROUTER_V2_TESTNET);

        vm.stopBroadcast();
    }

    function deployAndConfigure() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        MockUSDT usdt = new MockUSDT();
        BitLuck bitluck = new BitLuck(address(usdt), PANCAKE_ROUTER_V2_TESTNET);

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
