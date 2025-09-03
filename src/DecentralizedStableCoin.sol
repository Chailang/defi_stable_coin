// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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
// view & pure functions
pragma solidity 0.8.30;

import {ERC20Burnable,ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
contract DecentralizedStableCoin is ERC20Burnable,Ownable {
    // Errors
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();//销毁数量超过余额
    error DecentralizedStableCoin__NotZeroAddress();
    // Type Declarations

    // Events
    event Minted(address indexed minter, uint256 amount);
    event Burned(address indexed burner, uint256 amount);
    // State Variables

    
    // Functions
    constructor() ERC20("Decentralized Stable Coin", "DSC") Ownable(msg.sender) {
        // mint initial supply to contract creator for demo purposes
    }

    /**
     * @param amount The amount of DSC to burn
     * @notice Only the owner (i.e. the DSC engine) can burn DSC
     */
    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);
        if (amount > balance) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(amount);
        emit Burned(msg.sender, amount);
    }
    /**
     * @param to The address to mint DSC to
     * @param amount The amount of DSC to mint
     * @notice Only the owner (i.e. the DSC engine) can mint new DSC
     */
    function mint(
        address to, 
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(to, amount);
        emit Minted(msg.sender, amount);
        return true;
    }

}