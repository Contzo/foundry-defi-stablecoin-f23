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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol"; 

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
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address tokenAddress => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_dscToken;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount); 
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__NeedsMoreThenZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TransferFailed(); 
    error DSCEngine__TokenAddressIsNotAllowed();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThenZero(uint256 _amount) {
        if (_amount == 0) revert DSCEngine__NeedsMoreThenZero();
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenAddressIsNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory _allowedTokenAddresses, address[] memory _priceFeedsAddresses, address _dscAddress) {
        if (_allowedTokenAddresses.length != _priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < _allowedTokenAddresses.length; i++) {
            s_priceFeeds[_allowedTokenAddresses[i]] = _priceFeedsAddresses[i];
        }

        i_dscToken = DecentralizedStableCoin(_dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI pattern
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral  The amount of collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
        moreThenZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool transferSuccess = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if(!transferSuccess){
            revert DSCEngine__TransferFailed() ; 
        }
    }

    function redeemCollateral() external {}

    function mintDsc() external {}

    function redeemCollateralForDsc() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
