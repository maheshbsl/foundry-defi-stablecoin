// SPDX-License-Identifier: MIT

// what are invariants?

// 1. The total supply of the DSC should always be less than the total value of the collateral
// 2. Getter view functions should never revert

pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract TestInvariant is StdInvariant, Test {
    DeployDsc deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    uint256 deployerKey;

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        // targetContract(address(dscEngine));

        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        // get the total value of the collateral
        // get the total supply of the dsc (debt)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));

        // calculate the value of those tokens
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);



        console.log("timeMintisCalled", handler.timesMintCalled());
        console.log("total eth", totalWethDeposited);
        console.log("total btc", totalWbtcDeposited);
        console.log("total supply", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
