// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {MockV3Aggregator} from "test/Mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {

    uint8 public constant DECIMAL = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }    
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
       sepoliaNetworkConfig = NetworkConfig({
        wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
        wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
        weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
        wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
        deployerKey: vm.envUint("PRIVATE_KEY")
    });
    
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // if priceFeed is already set , return the existing config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        //otherwise, deploy a mock priceFeed
        vm.startBroadcast();
       // deploy a mock price feed for eth
        MockV3Aggregator mockEthUsdPriceFeed = new MockV3Aggregator(DECIMAL, ETH_USD_PRICE);
        // deploy a mock eth erc-20 token
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
      
       // deploy a mock pricefeed for btc
        MockV3Aggregator mockBtcUsdPriceFeed = new MockV3Aggregator(DECIMAL, BTC_USD_PRICE);
        // deploy a mock btc erc-20 token
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();

        return NetworkConfig ({
            wethUsdPriceFeed: address(mockEthUsdPriceFeed),
            wbtcUsdPriceFeed: address(mockBtcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

}