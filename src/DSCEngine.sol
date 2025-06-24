// SPDX-License-Identifier: MIT
/**
 * - Inside a sol file contract elements should be laid like this:
	1. Pragma statements
	2. Import statements
	3. Events
	4. Errors
	5. Interfaces
	6. Libraries
	7. Contracts
- Inside each contract we have this order of declaration:
	1. Type declaration
	2. State variables
	3. Events
	4. Errors
	5. Modifiers
	6. Functions
- Also functions inside a contract should be declared like this:
	1. constructor
	2. receive function (if exists)
	3. fallback function (if exists)
	4. external
	5. public
	6. internal
	7. private
	8. view & pure functions
 */
pragma solidity ^0.8.20;

/**
 * @title DSCEngine
 * @author Ilie Razvan
 *
 * The system is designed to ba as minimal as possible, and have the tokens maintain $1 pegged.
 * This stable coin has the following properties:
 *  - Exogenous Collateral
 *  - Dollar pegged
 *  - Algorithmically minted and burned tokens
 *
 * Our DSC system should always be "overcollateralized". At no point should the value of all the collateral should be less then the minted DSC
 * @notice this contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing.
 * @notice This contract is Very loosely based on the MakerDAO (DAI) system
 */
contract DSCEngine {
    function depositCollateralAndMintDsc() external {}

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThenZero();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThenZero(uint256 _amount) {
        if (_amount == 0) revert DSCEngine__NeedsMoreThenZero();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     *
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral  The amount of collateral to deposit
     */
    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    ) external moreThenZero(_amountCollateral) {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function redeemCollateralForDsc() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
