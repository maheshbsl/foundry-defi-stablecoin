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

    /////////////////
    //State Variables//
    ///////////////////

    uint256 private constant ADDITIONAL_PRICE_PRICISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

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
        address indexed user, address indexed tokaenCollateralAddress, uint256 indexed amountCollateral
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
     * @param tokenCollateralAddres The address of the token to deposit as Collateral
     * @param amountCollateral The amount of collateral user wants to deposit
     *
     */
    function depositCollateral(address tokenCollateralAddres, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isTokenAllowed(tokenCollateralAddres)
    {
        /**
         *  update the amount of collateral user has deposited for the given token
         *         the value is added to the existing collateral balance which is stored
         *         in the s_collateralDeposited mapping
         */
        s_collateralDeposited[msg.sender][tokenCollateralAddres] += amountCollateral;
        // emit the event
        emit CollateralDeposited(msg.sender, tokenCollateralAddres, amountCollateral);

        (bool success) = IERC20(tokenCollateralAddres).transferFrom(msg.sender, address(this), amountCollateral);
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
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);

        // Transfer the collateral to user
        (bool success) = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
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

    function burnDsc(uint256 amount ) public  moreThanZero(amount)
    {
        // update the mintedDSC value in the mapping
        s_DSCMinted[msg.sender] -= amount;
        (bool success) = i_Dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////////////
    // Internal Functions/
    //////////////////////

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 totalCollaratalValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollaratalValueInUsd = _getAccountCollateralValue(user);
        return (totalDscMinted, totalCollaratalValueInUsd);
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

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        hF = (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
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

    function _getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token in the `s_collateralTokens` array,
        // get the amount they have deposited, and map it to he price to get the usd value

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd = getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // if 1 ETH = 1000, Chainlink will return (1000 * 1e8)
        // so we have to make it 1e18 to make it compaitalbe with our amount which will be in 1e18
        // and finally divide by 1e18 to get a usd value
        return ((uint256(price) * ADDITIONAL_PRICE_PRICISION) * amount) / PRECISION;
    }
}
