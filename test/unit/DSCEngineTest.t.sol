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
    address weth; 

    address public USER = makeAddr("user"); 
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; 
    uint256 public constant INITIAL_AMOUNT = 1000 ether ; 

    function setUp() public{
        deployer = new DeployDSC() ; 
        (coin, engine, helperConfig)= deployer.run() ; 
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig() ; 
        ERC20Mock(weth).mint(USER, INITIAL_AMOUNT); // mint some ETH to the USER address for testing
    }

    modifier grantEnginePermissionToSpendFunds(address _engine, address _token, uint256 _amount, address _user){
        vm.startPrank(_user);
        ERC20Mock(_token).approve(_engine, _amount);
        vm.stopPrank();
        _;
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

    function testUserInitiallyHasZeroCollateralValue() public view {
        uint256 expectedInitialCollateralValue = 0 ; 
        uint256 actualCollateralValue = engine.getAccountCollateralValueInUSD(USER) ; 
        assertEq(expectedInitialCollateralValue, actualCollateralValue) ; 
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
}
