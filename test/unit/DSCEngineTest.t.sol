// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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
    uint256 public constant STARTING_ERC_20_BALANCE = 100 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC_20_BALANCE);
    }

    ///////////////////////
    /// constructor tests //
    ///////////////////////

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenLengthsDoesntMatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(btcUsdPriceFeed);
        priceFeedAddresses.push(ethUsdPriceFeed);

        // here we are adding only one token to the token addresses array and
        // adding two addresses to the priceFeed addresses array
        // in the constructor it ensures that the lenght of these two arrays are same
        // to make sure the coordination

        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressesAndPriceFeedsAddressesMustBeSameLength.selector);
        // now call the constructor
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        // this should now reverts
        console.log(tokenAddresses.length); // 1
        console.log(priceFeedAddresses.length); // 2
    }

    //////////////////
    /// price tests //
    //////////////////

    // eth => usd
    function testGetUsdValue() public view {
        uint256 ethAmount = 1 ether;
        //   2000 * 15e18 = 30000
        uint256 expectedUsd = 2000;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assert(expectedUsd == actualUsd);
        console.log(actualUsd);
    }

    // usd => eth
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100;

        uint256 expectedToken = 0.05 ether;
        uint256 actualToken = engine.getTokenAmountFromUsd(weth, usdAmount);

        // let's test that these two are same or not
        assertEq(expectedToken, actualToken);

        console.log(expectedToken); // 5e16
        console.log(actualToken); // 5e16
    }

    //////////////////////
    /// deposit collateral tests //
    //////////////////////

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

    // test if the depositCollateral function reverts if you try to deposit a invalid token
    function testRevertsWithUnapprovedCollateral() public {
        // this test passes because the `ranToken` has not been approved  as the collateral in the DSCEngine
        // let's create a token
        ERC20Mock ranToken = new ERC20Mock("RandomToken", "RTK", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);

        // ERC20Mock(ranToken).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);

        console.log(address(ranToken));
    }

    /**
     * @dev In test we have to deposit collateral again and again,
     * this modifier will help you do this
     */
    modifier depositCollateral() {
        // simulate as USER
        vm.startPrank(USER);

        // allow dscengien to transfer collateral
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        // deposit the collateral
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // stop simulating
        vm.stopPrank();
        _; // execute the remaining function
    }

    function testRevertsIfCollateralZero() public depositCollateral {
        //     // simulate as user
        //     vm.startPrank(USER);

        //     // allow dscengine to transfer amount collateral
        //     ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        //    // deposit collateral
        //    engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // check for deposit success
        uint256 userCollateral = engine.s_collateralDeposited(USER, weth);
        assertEq(userCollateral, AMOUNT_COLLATERAL);

        //check for reverts if collateral zero
        //    vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        //    //deposit with zero value
        //    engine.depositCollateral(weth, 0);

        vm.stopPrank();
        console.log(userCollateral);
        console.log(AMOUNT_COLLATERAL);
    }

    // function to test user can deposit collateral and can get information about it
    function testUserCanDepositCollateralAndGetInformation() public depositCollateral {
        // // simulate a user
        // vm.startPrank(USER);

        // // allows engine to transfer amount collateral
        // ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        // //deposit the collateral
        // engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // get the deposit infromation about USER
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd, uint256 totalCollateralAmount) =
            engine.getAccountInformation(USER);

        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assert(totalCollateralAmount == AMOUNT_COLLATERAL);
        // uint256 expectedDscMinted = 0;
        // assert the values
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
        //   assertEq(totalDscMinted, expectedDscMinted);

        console.log(expectedDepositAmount);
        console.log(totalDscMinted);
        console.log(AMOUNT_COLLATERAL);
    }

    // function to test helthfactor function is doing well
    function testHealthFactor() public {
        uint256 dsctoMint = 2 ether;

        //simulate as USER
        vm.startPrank(USER);

        // allow engine to transfer collateral
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        // deposit collateral
        engine.depositCollateral(weth, AMOUNT_COLLATERAL); // 10ether
        // mint some token (collateral is 10 so lets mint 2)
        engine.mintDsc(dsctoMint);

        //get user healthfactor
        uint256 healthfactor = engine.getHealthFactor(USER);

        // assert the healthfactor with min_healthfactor
        assert(healthfactor >= MIN_HEALTH_FACTOR);

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd,) = engine.getAccountInformation(USER);
        console.log("totalCollateralValueInUsd", totalCollateralValueInUsd);
        console.log("totalDscMinted", totalDscMinted);
        console.log("amountCollateral", AMOUNT_COLLATERAL);

        console.log("health factor", healthfactor, "min health factor",  MIN_HEALTH_FACTOR);
    }
}
