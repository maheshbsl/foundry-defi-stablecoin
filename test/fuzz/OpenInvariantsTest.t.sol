// SPDX-License-Identifier: MIT

// // what are invariants?

// // 1. The total supply of the DSC should always be less than the total value of the collateral
// // 2. Getter view functions should never revert

pragma solidity 0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDsc} from "script/DeployDsc.s.sol";
// import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// contract OpenTestInvariant is StdInvariant, Test {
//     DeployDsc deployer;
//     DSCEngine dscEngine;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;
//     address ethUsdPriceFeed;
//     address btcUsdPriceFeed;
//     uint256 deployerKey;

//     function setUp() external {
//         deployer = new DeployDsc();
//         (dsc, dscEngine, config) = deployer.run();
//         (ethUsdPriceFeed,btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
//         // get the total value of the collateral
//         // get the total supply of the dsc (debt)

//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dscEngine));
//         uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));

//         assert(totalWethDeposited + totalWbtcDeposited >= totalSupply);
//     }
// }
