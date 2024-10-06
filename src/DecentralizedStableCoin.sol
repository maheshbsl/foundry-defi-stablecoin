// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title DecentralizedStabelCoin
 * @author maheshbsl
 * collateral : Exogenous (BTC & ETH)
 * minting : Algorithmic
 * relative stability : pegged to usd
 *
 * This is the contract that is meant to be governed by DSCEngine.
 * This contract is just the erc20 implementation of our stable system.
 *
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /**
     * @dev The burning amount must be greater than zero.
     */
    error DecentralizedStabelCoin_MustMeMoreThanZero();

    /**
     * @dev Ensure that buring amount doesn't exceed the balance.
     */
    error DecentralizedStabelCoin_BurnAmountExceedsBalance();

    /**
     * @dev Ensure that no zero address is allowed
     */
    error DecentralizedStabelCoin_NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    /**
     * @param _amount The amount of token to burn
     * @dev Ensure that the burn amount is greater than zero
     * @dev Ensure that the burn amount doesn't exceed the balance
     * Call the burn funcion from parent contract
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStabelCoin_MustMeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStabelCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
    /**
     * @param _to The address to mint the token
     * @param _amount amount of token
     * @dev Ensure that `to` is not a zero address
     * @dev The amount must be greater than zero
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStabelCoin_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStabelCoin_MustMeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
