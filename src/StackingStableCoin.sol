// SPDX-License-Identifier: MIT
/**
 * - Inside a sol file contract elements should be laid like this:
 * 	1. Pragma statements
 * 	2. Import statements
 * 	3. Events
 * 	4. Errors
 * 	5. Interfaces
 * 	6. Libraries
 * 	7. Contracts
 * - Inside each contract we have this order of declaration:
 * 	1. Type declaration
 * 	2. State variables
 * 	3. Events
 * 	4. Errors
 * 	5. Modifiers
 * 	6. Functions
 * - Also functions inside a contract should be declared like this:
 * 	1. constructor
 * 	2. receive function (if exists)
 * 	3. fallback function (if exists)
 * 	4. external
 * 	5. public
 * 	6. internal
 * 	7. private
 * 	8. view & pure functions
 */
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Stacking Stable Token 
 * @author Ilie Razvan
 * @notice - this ERC20 token is used to provide ownership of stake from a DSC pool
 *
 * This is the contract is governed by the DSCYieldPool contract 
 */
contract StackingStableCoin is ERC20Burnable, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error StackStableCoin__MustBeMoreThenZero();
    error StackStableCoin__BurnAmountExceedsBalance();
    error StackStableCoin__NoZeroAddress();

    constructor() ERC20("Stacked Stable Coin", "SDSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert StackStableCoin__MustBeMoreThenZero();
        }

        uint256 balance = balanceOf(msg.sender);
        if (balance < _amount) {
            revert StackStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount); // use thee burn function from the parent
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StackStableCoin__NoZeroAddress();
        }
        if (_amount <= 0) {
            revert StackStableCoin__MustBeMoreThenZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
