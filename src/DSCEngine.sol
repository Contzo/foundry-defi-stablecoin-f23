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
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol"; 
import {Test, console} from "forge-std/Test.sol";
import {StackingPool} from "./StackingPool.sol"; 

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
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface; 
    struct OracleStatus{
        int256 price; 
        bool paused; 
    }
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address tokenAddress => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_dscToken;
    StackingPool private immutable i_dscYieldPool; 
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) s_DSCMinted;
    mapping(address collateralToken => int256 lastValidCollateralPrice) s_collateralLastValidPrices ; 
    address[] private s_collateralTokens;
    uint256 private s_circuitBrakeTimeStamp ; 
    uint256 private constant ADDITIONAL_PRICE_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 5e17;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10e16 ; // 10%
    uint256 private constant DEPOSIT_FEE = 5e16;  // 5% 
    int256 private constant ALLOWED_PRICE_DROP = 20e16; // 20%
    uint256 private constant CIRCUIT_BRAKE_COOLDOWN = 1 hours; 
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to,address indexed tokenCollateralAddress,  uint256  amountCollateral); 

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__NeedsMoreThenZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__TokenAddressIsNotAllowed();
    error DSCEngine__BrakesHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk() ; 
    error DSCEngine__HealthFactorNotImproved() ; 
    error DSCEngine__PriceIsZero(); 
    error DSCEngine__CircuitBrake_PriceDroppedToMuch_RestoringIn(uint256 cooldown) ;
    error DSCEngine__ApprovalFailed() ; 

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
    modifier circuitBrakeActiveCheck(){
        if(s_circuitBrakeTimeStamp != 0 && block.timestamp < s_circuitBrakeTimeStamp + CIRCUIT_BRAKE_COOLDOWN){
            revert DSCEngine__CircuitBrake_PriceDroppedToMuch_RestoringIn(s_circuitBrakeTimeStamp + CIRCUIT_BRAKE_COOLDOWN - block.timestamp); 
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory _allowedTokenAddresses, address[] memory _priceFeedsAddresses, address _dscAddress, address _DSCYieldPool) {
        if (_allowedTokenAddresses.length != _priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < _allowedTokenAddresses.length; i++) {
            s_priceFeeds[_allowedTokenAddresses[i]] = _priceFeedsAddresses[i];
            (, int256 lastValidPrice,,,) = AggregatorV3Interface(_priceFeedsAddresses[i]).stalePriceCheck() ; 
            s_collateralLastValidPrices[_allowedTokenAddresses[i]] = lastValidPrice; 
            s_collateralTokens.push(_allowedTokenAddresses[i]);
        }

        i_dscToken = DecentralizedStableCoin(_dscAddress);
        i_dscYieldPool = StackingPool(_DSCYieldPool) ;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @param tokenCollateralAddress the address of the token we want to deposit
     * @param amountCollateral the amount we want to deposit as collateral
     * @param amountDscToMint the DSC amount the user wants to mint.  
     * @notice this function calls both deposit collateral and mint DSC
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint); 
    }

    /**
     * @notice follows CEI pattern
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral  The amount of collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThenZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        uint256 depositFee = (_amountCollateral* DEPOSIT_FEE) / PRECISION ; 
        uint256 netCollateralDeposit = _amountCollateral - depositFee;
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += netCollateralDeposit;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, netCollateralDeposit);
        //Effect 
        bool transferSuccess =
            IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!transferSuccess) {
            revert DSCEngine__TransferFailed();
        }
        _fundDscYieldPoolFromDeposit(depositFee, _tokenCollateralAddress);
    }

    function calculateHealthFactor(uint256 collateralValueInUsd, uint256 mintedDSC) public pure returns(uint256 healthFactor){
        if(mintedDSC == 0) return type(uint256).max ;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / PRECISION;
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / mintedDSC;
    }
    /**
     * @notice the health factor of the user needs to remain > 1 after the redeeming
     * @param tokenCollateralAddress the address of the token the user wants to redeem
     * @param amountCollateral the amount of the collateral token, the user wants to redeem. 
     * @notice CEI: Check, Effects, Interactions
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThenZero(amountCollateral) nonReentrant circuitBrakeActiveCheck {
       _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender); // user redeems its own collateral
      // check if the health factor is still > 1 
        _revertIfHealthFactorIsBroken(msg.sender); 
    }

    /**
     * @notice Follows CEI
     * @param amountDscToMint - The amount of decentralized stable coin to mint
     * @notice They must have more collateral then the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThenZero(amountDscToMint) nonReentrant circuitBrakeActiveCheck {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender); // check if the newly minted DSC will brake the health factor
        bool successMinted = i_dscToken.mint(msg.sender, amountDscToMint);
        if (!successMinted) revert DSCEngine__MintFailed();
    }

    /**
     * @notice this function should only be used for liquidation test, will be removed in production
     */
    // function unsafeMintDsc(address _user, uint256 _amountDSCToMint) external{
    //     s_DSCMinted[_user] += _amountDSCToMint; 
    //     bool successMinted = i_dscToken.mint(_user, _amountDSCToMint); 
    //     if (!successMinted) revert DSCEngine__MintFailed();
    // }
    /**
     * @param tokenCollateralAddress - the address of the token used as collateral
     * @param amountCollateral - the amount of collateral to redeem. 
     * @param amountDSCToBurn - the amount of DSC we burn for redeeming the collateral.
     * @notice the health factor of the user is checked in the both redeem and burn functions
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn) external circuitBrakeActiveCheck {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @notice burns some amount of DSC 
     * @notice we might not have to check the health factor again because burning DSC shouldn't result in a health factor < 1. 
     */
    function burnDSC(uint256 _amount) public moreThenZero(_amount) {
        _burnDSC(_amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // this might never ever hit 
    }

    /**
     * @param collateral - the collateral ER20 token address we want to liquidate
     * @param user - the user we want to liquidate with a health factor below MIN_HEALTH_FACTOR
     * @param deptToCover - the amount of dept the arbitrageur want to cover in DSC
     * @notice You can partially liquidate
     * @notice The arbitrageur will get a liquidation bonus
     * @notice This function assumes that the protocol is roughly 200% overcollateralized. 
     * @notice A know bug would if the protocol were only 100% collateralize, then we would not be able to pay liquidation incentives. 
     * @notice follow CEI
     */
    function liquidate(address collateral, address user, uint256 deptToCover) external  moreThenZero(deptToCover) nonReentrant circuitBrakeActiveCheck {
        uint256 startingHealthFactor = _healthFactor(user);
        // check if the user can be liquidated
        if(startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk() ; 
        } 
        uint256 tokenAmountFromDeptCovered = getTokenAmountFromUSD(collateral, deptToCover);
        uint256 liquidationBonus = (tokenAmountFromDeptCovered * LIQUIDATION_BONUS) / PRECISION; 
        uint256 totalCollateralToRedeem = tokenAmountFromDeptCovered + liquidationBonus ; 
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDSC(deptToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // check is liquidation improved the health factor of the user dept
        if(endingUserHealthFactor < startingHealthFactor) { 
            revert DSCEngine__HealthFactorNotImproved() ; 
        }
        // also revert if the arbitrageur health factor broke as a result of trying to liquidate the user position
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external  returns(uint256 healthFactor){
        healthFactor = _healthFactor(user);
    }

    function getAccountCollateralValueInUSD(address _user) public circuitBrakeActiveCheck  returns (uint256 totalUSDValue) {
        // loop through each collateral token the user has, and map it to the price in order to get the USD.
        uint256 collateralTokensLength = s_collateralTokens.length;
        for (uint256 i = 0; i < collateralTokensLength; i++) {
            address token = s_collateralTokens[i];
            uint256 tokenAmount = s_collateralDeposited[_user][token];
            totalUSDValue += getUSDValue(token, tokenAmount);
        }
    }

    function getUSDValue(address _token, uint256 _amount) public  returns (uint256 USDValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        int256 lastGoodPrice = s_collateralLastValidPrices[_token]; 
        OracleStatus memory status = _updatePrice(priceFeed,_token,  lastGoodPrice);
        if(status.paused){
            revert DSCEngine__CircuitBrake_PriceDroppedToMuch_RestoringIn(s_circuitBrakeTimeStamp + CIRCUIT_BRAKE_COOLDOWN - block.timestamp) ;
        }
        s_collateralLastValidPrices[_token] = status.price ;
        USDValue = ((uint256(status.price) * ADDITIONAL_PRICE_FEED_PRECISION) * _amount) / PRECISION;
    }

    /**
     * @param token - the address of the ERC20 token we want receive for the USD amount 
     * @param usdAmountInWei - the amount of USD (in wei) we want to convert to token
     */
    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public  returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]) ; 
        (,int256 price,,,) = priceFeed.stalePriceCheck();
        s_collateralLastValidPrices[token] = price ;
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_PRICE_FEED_PRECISION);   
    }

    function getAccountInformation(address user) external  returns (uint256 totalDSCMinted, uint256 collateralValueInUSD){
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function updatePrice(AggregatorV3Interface priceFeed, address token,  int256 lastGoodPrice) external returns(OracleStatus memory){
        return _updatePrice(priceFeed,token, lastGoodPrice);
    }
    /*//////////////////////////////////////////////////////////////
                      PRIVATE & INTERNAL FUNCTION
    //////////////////////////////////////////////////////////////*/

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) internal circuitBrakeActiveCheck {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral ; 
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral); 
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed(); 
        }
    }

    /**
     * @dev Low-level internal function, do not call unless the function using it is checking the health factor 
     * being broken or not /
     */
    function _burnDSC(uint256 amountDSCToBurn, address onBehalf, address dscFrom) internal{
        s_DSCMinted[onBehalf] -= amountDSCToBurn; 

        bool success = i_dscToken.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if(!success) revert DSCEngine__TransferFailed() ; 

        i_dscToken.burn(amountDSCToBurn); 
    }
    function _getAccountInformation(address _user)
        private circuitBrakeActiveCheck
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[_user];
        collateralValueInUSD = getAccountCollateralValueInUSD(_user);
    }

    function _healthFactor(address user) private circuitBrakeActiveCheck returns (uint256 healthFactor) {
        // total DSC minted
        // total collateral value
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        healthFactor = calculateHealthFactor(collateralValueInUSD, totalDSCMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal  {
        // 1. Checks the health factor
        // 2. Revert if the health factor is <1
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrakesHealthFactor(healthFactor);
        }
    }

    /**
     * @notice - a function that will fetch the last price update. 
     * @notice - if the price drops to low 
     */
    function _updatePrice(AggregatorV3Interface priceFeed, address token, int256 lastGoodPrice) private  returns(OracleStatus memory){
        (, int256 newPrice,,,) = priceFeed.stalePriceCheck(); 
        if(s_circuitBrakeTimeStamp != 0 &&block.timestamp < s_circuitBrakeTimeStamp + CIRCUIT_BRAKE_COOLDOWN){
            return OracleStatus(type(int256).min, true) ; // still paused
        }
        console.log("Last good price", lastGoodPrice); 
        bool paused = _checkCircuitBreaker(lastGoodPrice, newPrice);
        if(paused){
            s_circuitBrakeTimeStamp = block.timestamp; 
            s_collateralLastValidPrices[token] = newPrice; 
            return OracleStatus(type(int256).min, true );  // trigger circuit brake 
        }
        return OracleStatus(newPrice, false); 
    }


    /**
     * @notice - a function that determines if the collateral price drop should impose a temporary circuit brake of the engine
     * @param lastGoodPrice - is the last price update that was withing the allowed price drop
     * @param newPrice - the new price that needs to be analyzed 
     */
    function _checkCircuitBreaker(int256 lastGoodPrice, int256 newPrice) private pure returns(bool){
        if(lastGoodPrice == 0) revert DSCEngine__PriceIsZero() ; 
        int256 maxPriceDrop = lastGoodPrice * ALLOWED_PRICE_DROP / int256(PRECISION); 
        int256 minThreshold = lastGoodPrice - maxPriceDrop ; 
        if(newPrice < minThreshold) return true ; 
        else return false ;
    }

    function _fundDscYieldPoolFromDeposit(uint256 _collateralDepositFee, address _collateralToken) internal { 
        // convert the fee to USD
        uint256 depositFeeUsdValue = getUSDValue(_collateralToken, _collateralDepositFee);
        // burn the collateral token used as fee 
        IERC20(_collateralToken).transfer(address(0), _collateralDepositFee);

        // Mint the DSC fee to the yield pool contract 
        i_dscToken.mint(address(i_dscYieldPool), depositFeeUsdValue); 

        i_dscYieldPool.fundStakePool(depositFeeUsdValue);
    }
    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
  function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dscToken);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }


 
}
