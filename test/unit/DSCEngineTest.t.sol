// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol"; 
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol" ; 
import {HelperConfig} from "../../script/HelperConfig.s.sol"; 
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test{
    DeployDSC deployer; 
    DecentralizedStableCoin coin; 
    DSCEngine engine ; 
    HelperConfig helperConfig ; 
    address ethUsdPriceFeed ; 
    address wbtcUsdPriceFeed;
    address weth; 

    address public USER = makeAddr("user"); 
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; 
    uint256 public constant INITIAL_AMOUNT = 1000 ether ; 

    function setUp() public{
        deployer = new DeployDSC() ; 
        (coin, engine, helperConfig)= deployer.run() ; 
        (ethUsdPriceFeed,wbtcUsdPriceFeed, weth,,) = helperConfig.activeNetworkConfig() ; 
        ERC20Mock(weth).mint(USER, INITIAL_AMOUNT); // mint some ETH to the USER address for testing
    }

    modifier grantEnginePermissionToSpendFunds(address _engine, address _token, uint256 _amount, address _user){
        vm.startPrank(_user);
        ERC20Mock(_token).approve(_engine, _amount);
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses ; 
    address[] public priceFeedAddresses; 
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public{
        // Setup 
        tokenAddresses.push(weth) ; 
        priceFeedAddresses.push(ethUsdPriceFeed); 
        priceFeedAddresses.push(wbtcUsdPriceFeed) ; 
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(coin)); 
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/ 

    function testGetUsdValue() public view {
        // Setup
       uint256 ethAmount = 15e18 ; // 15e18 * 2000/ETH = 30,000e18 USD 
       uint256 expectedUsd = 30_000e18 ; 
       // Execute 
       uint256 UsdAmount = engine.getUSDValue(weth, ethAmount);
       //Assert
        assertEq(expectedUsd, UsdAmount);
    }

    function testGetTokenAmountFromUSD() public view {
        // Set up 
        uint256 usdAmount = 100 ether; 
        // $2,000/ETH, $100 = 0.05 ETH ; 
        uint256 expectedETHAmount = 0.05 ether ; 
        // Execute 
        uint256 actualWeth = engine.getTokenAmountFromUSD(weth, usdAmount); 
        //Assert 
        assertEq(expectedETHAmount, actualWeth); 
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertIfCollateralZero() public{
        vm.startPrank(USER);
        // Setup
        ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL); // approve the engine to transfer some amount of tokens of the USER.
        //Execute && Assert
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThenZero.selector); 
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositWithUnauthorizedToken() public {
        // Set up 
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, INITIAL_AMOUNT) ;  // mock token we that is not 
        // Execute and Assert 
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressIsNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank(); 
    }

    function testUserInitiallyHasZeroCollateralValue() public view {
        uint256 expectedInitialCollateralValue = 0 ; 
        uint256 actualCollateralValue = engine.getAccountCollateralValueInUSD(USER) ; 
        assertEq(expectedInitialCollateralValue, actualCollateralValue) ; 
    }

    modifier depositCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL) ; 
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _; 
    }
    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral{
        // Act
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        //Assert
        uint256 expectedDSCMinted = 0 ; 
        uint256 expectedCollateralTokens= engine.getTokenAmountFromUSD(weth,collateralValueInUsd); 
        assertEq(totalDSCMinted, expectedDSCMinted); 
        assertEq(AMOUNT_COLLATERAL, expectedCollateralTokens); 
    }

     function testDepositCollateralAndMintDSCFailsIfNotEnoughCollateral() public grantEnginePermissionToSpendFunds(address(engine), weth, AMOUNT_COLLATERAL, USER){
        uint256 DSCToMint = 15_000 ether ; 
        uint256 collateralValueInUsd = engine.getUSDValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(collateralValueInUsd, DSCToMint);
        vm.prank(USER); 
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BrakesHealthFactor.selector,
                expectedHealthFactor
            )
        );
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, DSCToMint);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDSC() public grantEnginePermissionToSpendFunds(address(engine), weth, AMOUNT_COLLATERAL, USER){
        // Setup
        uint256 DSCToMint = 1_000 ether; 
        uint256 expectedCollateralValueInUsd = engine.getUSDValue(weth, AMOUNT_COLLATERAL); 
        //Execute 
        vm.startPrank(USER);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, DSCToMint);
        vm.stopPrank();
        //Assert 
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        vm.assertEq(totalDSCMinted, DSCToMint);
        vm.assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }
    function testDepositAmount()  grantEnginePermissionToSpendFunds(address(engine), weth, AMOUNT_COLLATERAL, USER) public{
        // Setup was done in the modifier
        vm.startPrank(USER);
        // Act
        engine.depositCollateral(weth, AMOUNT_COLLATERAL); 
        //Assert
        uint256 expectedCollateralVale = engine.getUSDValue(weth,AMOUNT_COLLATERAL) ; 
        uint256 actualCollateralValue = engine.getAccountCollateralValueInUSD(USER);
        assertEq(expectedCollateralVale, actualCollateralValue);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRedeemCollateralForUserWithInfiniteHealthFactor() public depositCollateral(){
       //Setup 
       uint256 collateralToRedeem = 1 ether; 
       uint256 remainingCollateral = AMOUNT_COLLATERAL - collateralToRedeem; 
       uint256 expectedRemainingCollateralValueInUsd = engine.getUSDValue(weth, remainingCollateral);
       //Execute 
       vm.startPrank(USER); 
       engine.redeemCollateral(weth, collateralToRedeem);
       vm.stopPrank() ; 
       //Assert 
       uint256 remainingCollateralValueInUsd = engine.getAccountCollateralValueInUSD(USER);
        vm.assertEq(expectedRemainingCollateralValueInUsd, remainingCollateralValueInUsd);
    }

    function testRedeemingToMuchCollateralBrakesHF() public grantEnginePermissionToSpendFunds(address(engine), weth, AMOUNT_COLLATERAL, USER){
        // Setup
        uint256 DSCToMint = 10_000 ether ; 
        uint256 collateralToRedeem = 5 ether; 
        uint256 expectedRemainingCollateralValueInUsd = engine.getUSDValue(weth, (AMOUNT_COLLATERAL-collateralToRedeem));
        uint256 expectedBrokenHF = engine.calculateHealthFactor(expectedRemainingCollateralValueInUsd, DSCToMint);
        vm.startPrank(USER); 
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, DSCToMint);
        
        //Execute and assert 
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrakesHealthFactor.selector, expectedBrokenHF)); 
        engine.redeemCollateral(weth, collateralToRedeem);
    }

    modifier depositAndMintDSC(address user, uint256 amountDSCMint){
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL) ; 
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDSCMint);
        vm.stopPrank();
        _;       
    }

    function testRedeemCollateral() public depositAndMintDSC(USER, 1_000 ether){
        //Setup 
        uint256 collateralToRedeem = 1 ether; 
        uint256 expectedRemainingCollateralValueInUsd = engine.getUSDValue(weth, AMOUNT_COLLATERAL- collateralToRedeem);
        //Act 
        vm.startPrank(USER);
        engine.redeemCollateral(weth, collateralToRedeem);
        vm.stopPrank();
        //Assert
        uint256 remainingCollateralValueInUsd = engine.getAccountCollateralValueInUSD(USER);
        vm.assertEq(expectedRemainingCollateralValueInUsd, remainingCollateralValueInUsd);
    }

    function testRedeemCollateralForDSC() public depositAndMintDSC(USER, 1_000 ether) grantEnginePermissionToSpendFunds(address(engine),address(coin), 1_000 ether, USER){
        //Setup
        uint256 collateralToRedeem = 1 ether; 
        uint256 DSCToBurn = 100 ether; 
        uint256 expectedRemainingCollateralValueInUsd = engine.getUSDValue(weth, AMOUNT_COLLATERAL-collateralToRedeem);
        uint256 expectedRemainingDSC = 1_000 ether - DSCToBurn; 
        //Execute
        vm.startPrank(USER);
        engine.redeemCollateralForDsc(weth, collateralToRedeem, DSCToBurn);
        vm.stopPrank(); 
        //Assert 
        (uint256 remainingDSC, uint256 remainingCollateralValueInUsd) = engine.getAccountInformation(USER);
        vm.assertEq(expectedRemainingDSC, remainingDSC);
        vm.assertEq(expectedRemainingCollateralValueInUsd, remainingCollateralValueInUsd);
    }
    function testLiquidation() public depositAndMintDSC(USER, 10_000 ether){
        // Initiate some good dept first 
        // Initiate some arbitrageur account in the system. 
        // Make the user dept bad on purpose.
        // Liquidate the bad dept. 

    }
}
