// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {console} from "forge-std/Script.sol";

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
 * @title DSCEngine
 * @author Mahesh Busal
 *
 * The system is designed to be as minimal as possible,
 * and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine {
    /////////////////
    // Errors
    ///////////////////
    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedsAddressesMustBeSameLength();
    error DSCEngine_TokenNotAllowed();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorIsOk();
    error DSCEngine_HealthFactorNotImproved();

    /////////////////
    //State Variables//
    ///////////////////

    uint256 private constant ADDITIONAL_PRICE_PRICISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) public s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    DecentralizedStableCoin private immutable i_Dsc;
    address[] private s_collateralTokens;

    /////////////////
    //  Events   //
    ///////////////////

    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokaenCollateralAddress,
        uint256 amountCollateral
    );

    /////////////////
    // Modifiers
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }
        _; // continue the function execution
    }

    //    /**
    //     *
    //     * @param tokenAddresses The address of the token which will be deposited by user as collateral
    //     * @param priceFeedAddresses The address of the price feed associted with specific token
    //     * @dev If a invalid collateral token is entered by a user, `s_priceFeeds` mapping will return zero address
    //     * because there is not an associated priceFeed for that address , and reverts a function
    //     */
    modifier isTokenAllowed(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine_TokenNotAllowed();
        }
        _; // execute the rest of the function
    }

    /////////////////
    // Functions
    ///////////////////

    /**
     *
     * @param tokenAddresses The array of token contract addresses that will be supported as collateral
     * @param priceFeedAddresses The array of the priceFeeds contract addresses (like Chainlink)
     * @param dscAddress The address of the DecentralizedStableCoin
     * @dev Ensure that length of `tokenAddresses` is the same as length of `priceFeedAddresses`
     * @dev This ensures that every token address has their corresponding address.
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedsAddressesMustBeSameLength();
        }
        for (uint256 i; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_Dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////
    // External Functions
    ///////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as Collateral
     * @param amountCollateral The amount of collateral user wants to deposit
     * @param amountDscTOMint The amount of decentralized stablecoins user wants to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscTOMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscTOMint);
    }

    /**
     * depositCollateral()
     * @param tokenCollateralAddress The address of the token to deposit as Collateral
     * @param amountCollateral The amount of collateral user wants to deposit
     *
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isTokenAllowed(tokenCollateralAddress)
    {
        /**
         *  update the amount of collateral user has deposited for the given token
         *         the value is added to the existing collateral balance which is stored
         *         in the s_collateralDeposited mapping
         */
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // emit the event
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        (bool success) = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * redeemCollateral()
     * @param tokenCollateralAddress The address of the token collateral user wants to redeem
     * @param amountCollateral The amount of Collateral user wants to redeem
     * @dev health factor must be > 1 after collateral pulled
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * mintDsc()
     * @param amountDscToMint The amount of decentralized stablecoin User wants to mint
     * @dev make sure the amount is greater than zero
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) {
        //update the amount of DSC user want to mint
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_Dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        // update the mintedDSC value in the mapping
        _brunDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param collateral the token address that the user has used as collateral
     * @param user The user who is being liquidated
     * @param debetToCover The amount of usd which is equivalent to the amount of dscminted(borrowed)
     * Follows CEI : Check, Effets, Ineractions
     */
    function liquidate(address collateral, address user, uint256 debetToCover) external moreThanZero(debetToCover) {
        // if you wants to liquidate the user, you first needs to check the user's health factor, to ensure they are liquidateable
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorIsOk();
        }
        // we want ot burn their dsc "debt"
        // and take their collateral
        // bad user: $140 of ETH, $100 of DSC
        // debt to cover == $100
        // $100 of DSC == how much of ETH?
        // if the price of eth is $2000
        // then $100 is equal to 0.05 eth

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debetToCover);
        // we want to give 10% bonus to liquidators
        // which means we are giving $110 for $100 of debt
        // we have calculated that if the debt is equal to 0.05 then
        // the collateral bonus will be 0.005 of token  (0.05 * 10) / 100 == 0.005
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // now we have to redeem the total collateral which will be (tokenAmountFromDebtCovered + bonusCollateral)
        // which is (0.05 + 0.005) = 0.055 of token will be given to liquidator in total
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        // now we need to burn the dsc
        _brunDsc(debetToCover, user, msg.sender);
        // now check for the health factor again
        // if the health factor not impoved then reverts
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        // if the healthfactor of the liquidator is affected by liquidating the user, whe shouldn't allow the liquidator to liquidate the user
        // we will reverts
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////////
    // Internal Functions/
    //////////////////////

    /**
     *
     * @param amountDscToBurn The total amount of dsc to burn
     * @param onBehalfOf The address of the user who is being liquidated
     * @param dscFrom The address of the liquidator who is bunning their token, on behalfof the user
     */
    function _brunDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // update the mintedDSC value in the mapping
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        (bool success) = i_Dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        i_Dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // Transfer the collateral to user
        (bool success) = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 totalCollaratalValueInUsd, uint256 totalCollaratalAmount)
    {
        totalDscMinted = s_DSCMinted[user];
        (totalCollaratalValueInUsd, totalCollaratalAmount) = _getAccountCollateralValue(user);
        return (totalDscMinted, totalCollaratalValueInUsd, totalCollaratalAmount);
    }

    /**
     * @param user The address which is being check for health factor
     * @dev Return how close to liquidition the user is
     *
     */
    function _healthFactor(address user) internal view returns (uint256 hF) {
        // to check health factor we will need
        // 1 .Total dsc minted by user
        // 2 Total value of collateral user has deposited

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd, uint256 totalCollateralAmount) =
            _getAccountInformation(user);
            console.log(totalCollateralValueInUsd);

        uint256 collateralAdjustedForThreshold = (totalCollateralAmount * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        hF = ((collateralAdjustedForThreshold) / totalDscMinted);
        return hF;
    }

    // check health factor (do they if enough collateral)
    // IF NOT REVERTS
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////
    // Public  Functions/
    //////////////////////

    /**
     *
     * @param token eth
     * @param usdAmountInWei The amount of debt
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // now we have the current price of the token
        // we have to calculate amount of token which is equivalent to the value of debt
        // if price of eth(token) = $2000
        // and the debt is $100
        // 100 / 2000 = 0.05 eth(token)
        // (100e18 * 1e18) / (2000e8 * 1e10)
        uint256 amountOfTokenEquivalentToDebt =
            ((usdAmountInWei * PRECISION) * PRECISION) / (uint256(price) * ADDITIONAL_PRICE_PRICISION);
        return amountOfTokenEquivalentToDebt;
    }

    function _getAccountCollateralValue(address user)
        public
        view
        returns (uint256 totalCollateralValueInUsd, uint256 totalCollateralAmount)
    {
        // loop through each collateral token in the `s_collateralTokens` array,
        // get the amount they have deposited, and map it to he price to get the usd value

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralAmount += amount;
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return (totalCollateralValueInUsd, totalCollateralAmount);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // if 1 ETH = 1000, Chainlink will return (1000 * 1e8)
        // so we have to make it 1e18 to make it compaitalbe with our amount which will be in 1e18
        // and finally divide by 1e18 to get a usd value
        return ((uint256(price) * ADDITIONAL_PRICE_PRICISION) * amount) / (PRECISION * PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollaratalValueInUsd, uint256 totalCollateralAmount)
    {
        (totalDscMinted, totalCollaratalValueInUsd, totalCollateralAmount) = _getAccountInformation(user);
        return (totalDscMinted, totalCollaratalValueInUsd, totalCollateralAmount);
    }

    function getHealthFactor(address user) public view returns (uint256 health) {
        health = _healthFactor(user);
    }
}
