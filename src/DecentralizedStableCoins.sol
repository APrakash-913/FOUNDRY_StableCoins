// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/////////////
// IMPORTS //
/////////////
import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stablecoins
 * @author Abhinav Prakash
 * @notice Collateral: Exogenous (ETH & BTC)
 *         Minting: Algorithmic
 *         Relative Stability : Pegged to USD
 *
 * 👉It is meant to be governed by DSCEngine                                                                                                                                                                                                                         .
 * 👉This is a basic implementation of a Decentralized Stablecoin.
 * 👉It is an ERC20 Implementation.
 */
contract DecentralizedStableCoins is ERC20Burnable, Ownable {
    ///////////
    // ERROR //
    ///////////
    error DecentralizedStableCoins__AmountMustBeMoreThanZero();
    error DecentralizedStableCoins__AmountExceedsBalance();
    error DecentralizedStableCoins__InvalidZeroAddress();

    /////////////////
    // CONSTRUCTOR //
    /////////////////
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoins__AmountMustBeMoreThanZero();
        }

        if (_amount > balance) {
            revert DecentralizedStableCoins__AmountExceedsBalance();
        }
        // 📝 Use the "burn()" function of Parent Contract.
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoins__InvalidZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStableCoins__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
