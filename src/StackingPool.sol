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


/**
 * @title Yield Pool for DSC token
 * @author Ilie Razvan 
 * @notice This contract will allow a user to stack some DSC. In exchange the user will receive a stack Stable Coin (SDSC) token.
 * @notice The reward pool is constructed of fees collected by the DSC engine on minting and depositing. The fees are added to the pool as soon as they are collected. 
 * @notice The yielding mechanism is linear emission per user one, in order to distribute rewards smoothly over time, based on how much the user have stacked and and for how hold they hold their share of the stake.
 */

// Functions:
// - Deposit/Stack DSC 
// - Withdraw 
// - claim rewards
// - view claimable rewards
// - fund reward pool
// - adjust emission rate.
pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {StackingStableCoin} from "./StackingStableCoin.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

contract StackingPool is Ownable, ReentrancyGuard{
    /*//////////////////////////////////////////////////////////////
                            STATE_VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private s_totalDSCStacked; 
    uint256 private s_yieldPoolBalance ; 
    mapping(address user => uint256 lastClaimed) private s_lastRewardClaimedTimeStamp ; 
    StackingStableCoin immutable i_SDSC ; 
    DecentralizedStableCoin immutable i_DSC; 
    uint256 private emissionPeriod ; 
    uint256 constant PRECISION = 1e18; 


    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DSCStacked(address indexed user,uint256 indexed amountDSCStaked); 
    event YieldClaimed(address indexed user, uint256 indexed yieldClaimed) ; 
    event DSCWithdraw(address indexed user, uint256 indexed withdrawDSC); 
    event YieldPoolFunded(address indexed source, uint256 indexed amount); 

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error StackingPool__TransferFailed();
    error StackingPool__MintingSDSCFailed();
    error StackingPool__NeedsMoreThenZero();
    error StackingPool__NotEnoughYield(uint256 yield);
    error StackingPool__InsufficientDSCInPool(); 
    error StakingPool__NoStakeForUser(address user) ;
    error StakingPool__NoYieldForUser(address user); 


    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThenZero(uint256 _amount){
        if(_amount <= 0) revert StackingPool__NeedsMoreThenZero() ; 
        _; 
    }
    constructor(address _poolTokenAddress, address _stableCoinAddress, uint256 _initialEmissionPeriod){
        i_SDSC = StackingStableCoin(_poolTokenAddress); 
        i_DSC = DecentralizedStableCoin(_stableCoinAddress); 
        emissionPeriod = _initialEmissionPeriod; 
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/   

    /**
     * @notice function the follows CEI
     * @param _amountDSCToStake the amount of DSC token a user want to stake (18 decimals precision)
     */
    function stakeDSC(uint256 _amountDSCToStake) external moreThenZero(_amountDSCToStake) nonReentrant {
        //Effect
        uint256 amountSDSCToMint ; 
        uint256 totalSDSCSupply = i_SDSC.totalSupply();
        if(s_totalDSCStacked == 0 || totalSDSCSupply == 0){
            amountSDSCToMint = _amountDSCToStake; 
        }
        else{
            amountSDSCToMint = (_amountDSCToStake * totalSDSCSupply) / s_totalDSCStacked; 
        }
        s_totalDSCStacked += _amountDSCToStake; 
        if(s_lastRewardClaimedTimeStamp[msg.sender] == 0){
            s_lastRewardClaimedTimeStamp[msg.sender] = block.timestamp;
        }
        emit DSCStacked(msg.sender, _amountDSCToStake); 

        //Interact 
        bool transferSuccess = i_DSC.transferFrom(msg.sender, address(this), _amountDSCToStake); 
        if(!transferSuccess) revert StackingPool__TransferFailed() ; 
        bool mintSuccess = i_SDSC.mint(msg.sender, amountSDSCToMint) ; 
        if(!mintSuccess) revert StackingPool__MintingSDSCFailed() ; 
    }

    /**
     * @notice the user burns some SDSC in order to receive some of all of his stake and the accumulated yield
     * @notice this follows the CEI pattern
     * @param _SDSCamountToBurn the amount of SDSC the user will burn for DSC
     */
    function withdraw(uint256 _SDSCamountToBurn) external moreThenZero(_SDSCamountToBurn) nonReentrant {
       //Effect 
       uint256 userDSCStake = _getStake(_SDSCamountToBurn);
       if(userDSCStake == 0)  revert StakingPool__NoStakeForUser(msg.sender) ;
       if(userDSCStake > i_DSC.balanceOf(address(this))) revert StackingPool__InsufficientDSCInPool() ; 
       s_totalDSCStacked -= userDSCStake; 
       uint256 userDSCYield= getUserReward(msg.sender);
       if(s_yieldPoolBalance < userDSCYield) revert StackingPool__NotEnoughYield(s_yieldPoolBalance) ; 
       s_yieldPoolBalance -= userDSCYield; 
       s_lastRewardClaimedTimeStamp[msg.sender] = block.timestamp; 
       uint256 totalDSCToWithdraw = userDSCStake + userDSCYield ; 
       emit YieldClaimed(msg.sender, userDSCYield) ; 
       emit DSCWithdraw(msg.sender, totalDSCToWithdraw); 

       //Interact 
       bool successDSCTransfer = i_DSC.transfer(msg.sender, totalDSCToWithdraw);
       if(!successDSCTransfer) revert StackingPool__TransferFailed() ; 
       bool successSDSCTransfer = i_SDSC.transferFrom(msg.sender, address(this), _SDSCamountToBurn);
       if(!successSDSCTransfer) revert StackingPool__TransferFailed() ; 
       i_SDSC.burn(_SDSCamountToBurn);
    }

    /**
     * @notice function used to retrieve the accumulated yield
     * @notice follows the CEI pattern
     */

    function claimYield() external nonReentrant{
        //Effect 
        uint256 userDSCYield = getUserReward(msg.sender);
        if(userDSCYield == 0)  revert StakingPool__NoYieldForUser(msg.sender); 
        if(s_yieldPoolBalance < userDSCYield) revert StackingPool__NotEnoughYield(s_yieldPoolBalance) ; 
        s_yieldPoolBalance -= userDSCYield ; 
        s_lastRewardClaimedTimeStamp[msg.sender] = block.timestamp; 
        emit YieldClaimed(msg.sender, userDSCYield) ; 

        //Interact
        bool transferSuccess = i_DSC.transfer(msg.sender, userDSCYield); 
        if(!transferSuccess) revert StackingPool__TransferFailed() ; 
    }

    /**
     * @notice function used to fund the yield pool 
     * @notice this function will mainly be called by the DSC engine, in order to fund the pool with the fees
     * @param _amountDSCToFund the amount of DSC that will fund the pool
     */
    function fundStakePool(uint256 _amountDSCToFund) external moreThenZero(_amountDSCToFund) nonReentrant onlyOwner{
        // this function uses a push pattern 
        // the funds are pushed from the engine, they are not pulled from the stake pool contract 
        // Effect 
        s_yieldPoolBalance +=_amountDSCToFund; 
        emit YieldPoolFunded(msg.sender, _amountDSCToFund); 
    }

    function adjustEmissionPeriod(uint256 _newEmissionPeriod) external onlyOwner moreThenZero(_newEmissionPeriod) nonReentrant() {
        emissionPeriod = _newEmissionPeriod ; 
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice determines the corresponding DSC share of the total pool for a given SDSC amount
     * @param _amountSDSC the amount of SDSC we want to convert to DSC share of the pool
     */
    function _getStake(uint256 _amountSDSC) internal view returns(uint256 stake){
        uint256 SDSCTotalSupply = i_SDSC.totalSupply();
       if(SDSCTotalSupply == 0 || s_totalDSCStacked == 0) return 0 ; 
        stake = (_amountSDSC * s_totalDSCStacked)/SDSCTotalSupply ; 
    }



    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice get the amount of DSC a user can claim from the yield pool
     */
    function getUserReward(address _user) public view returns(uint256 claimableDSC){
        // determine the amount a user can claim 
        uint256 lastClaimedTimestamp = s_lastRewardClaimedTimeStamp[_user]; 
        if (block.timestamp <= lastClaimedTimestamp) return 0;
        uint256 currentGlobalEmissionRate = s_yieldPoolBalance/emissionPeriod ; 
        uint256 currentUserPoolStake = getUserStake(_user);
        uint256 timeElapsedSinceLastClaim = block.timestamp - lastClaimedTimestamp; 
        uint256 stakeShare = (currentUserPoolStake * PRECISION) / s_totalDSCStacked; 
        claimableDSC = (timeElapsedSinceLastClaim * currentGlobalEmissionRate * stakeShare) / PRECISION; 
    }

    /**
     * @notice determine the stake share a user holds 
     */
    function getUserStake(address _user) public view returns(uint256 userStake) {
       uint256 currentUserSDSCBalance = i_SDSC.balanceOf(_user);
        userStake = _getStake(currentUserSDSCBalance);
    }

    function getTotalStakePool()public view returns(uint256 totalStakeBalance) {
       totalStakeBalance = s_totalDSCStacked;  
    }

    function getEmissionPeriod()public view returns(uint256){
       return emissionPeriod;  
    }
}