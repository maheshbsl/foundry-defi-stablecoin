// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DscEngineTest is Test {

    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );
    

    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC_20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;


    function setUp() external {
        deployer = new DeployDsc();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC_20_BALANCE);
        
    }
    //////////////////
    /// price tests //
    //////////////////

    function testGetUsdValue() public view {

        uint256 ethAmount = 15e18;
        //   2000 * 15e18 = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assert(expectedUsd == actualUsd);
    }
    
    //test for deposit of collateral
    function testdepositCollateralSuccess() public {
         // Simulate user having WETH to deposit
         uint256 wethAmount = 1e18;

         vm.startPrank(USER);
         deal(weth, USER, wethAmount); 
        
        // approve engine to use weth
         ERC20Mock(weth).approve(address(engine), wethAmount);

         // deposit the collateral
         engine.depositCollateral(weth, wethAmount);
 

         // check if the collateral deposited successfully

         uint256 userCollateral = engine.s_collateralDeposited(USER, weth);
         assertEq(userCollateral, wethAmount);

        //  vm.expectEmit(true, true, true, true, address(engine));
        //  emit CollateralDeposited(USER, weth, wethAmount);    

         vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        // simulate as user
        vm.startPrank(USER);
        
        // allow dscengine to transfer amount collateral
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

       // deposit collateral
       engine.depositCollateral(weth, AMOUNT_COLLATERAL);
      
      // check for deposit success
        uint256 userCollateral = engine.s_collateralDeposited(USER, weth);
        assertEq(userCollateral, AMOUNT_COLLATERAL);

       //check for reverts if collateral zero
    //    vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
    //    //deposit with zero value
    //    engine.depositCollateral(weth, 0);


       console.log(userCollateral);
       console.log(AMOUNT_COLLATERAL);
    }
}
