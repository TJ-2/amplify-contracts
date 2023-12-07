// SPDX-License-Identifier: MIT

// calculates the allocations of tokens to different investment pools

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "./interfaces/IBaseInvestmentPool.sol";
import "./interfaces/ITokenManager.sol";

contract Investmentogic {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;   

    uint256 public constant HUNDRED_PCT= 10000;
    uint256 public constant MIN_TX_LIMIT = 1000000; // $1
    uint256 public constant MAX_POOLS_TO_ADJUST = 3;  // sets the max number of poos that can be adjusted in one tx
    
    ITokenManager public tokenManager;

    address public tokenManagerContract;
    address priceFeed;
    address public gov;

    bool public isInitialized;

    constructor() public {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyTokenManager() {
        require(msg.sender == tokenManagerContract, "TokenManager: Forbidden");
        _;
    }

    function initialize(address _priceFeed, address _tokenManagerContract) external onlyGov {
        require(!isInitialized, "Already Initialized");
        isInitialized = true;
        priceFeed = _priceFeed;
        tokenManagerContract = _tokenManagerContract;
        tokenManager = ITokenManager(tokenManagerContract);
    }

    // Calculate the investment pool transactions such that the sum of the token balance deviations to target is minimised 
    function getPoolTransactions(address _token, uint256 _amount, bool isDeposit) external view onlyTokenManager returns(address[] memory, uint256[] memory){
        // Step 1 - get all the pools that use this token and setup return arrays
        address[] memory filteredPools = tokenManager.getFilteredInvestmentPools(_token);
        address[] memory txAddresses  = new address[](filteredPools.length);
        uint256[] memory txAmounts  = new uint256[](filteredPools.length);
        uint256 amount = _amount;

        // step 2 - total up the token targets for all of the pools that use this token
        uint256 totalTargetsAllPools = tokenManager.getTotalTokenTarget(_token);
        require(totalTargetsAllPools > 0,"FundManager: Invalid pool targets");
        
        for (uint256 i = 0; i < filteredPools.length; i++) { 
            uint256 thisPoolTarget = IBaseInvestmentPool(filteredPools[i]).getTargetAlpBalance(_token);            
            // Handle scenario where pool has a target of zero and tx is a withdrawl
            if(!isDeposit && thisPoolTarget <= 0){
                // check if any tokens remaining in this pool
                uint256 thisPoolBalance = IBaseInvestmentPool(filteredPools[i]).getTokenBalance(_token);
                if(thisPoolBalance > 0){
                    // if the remaining tokens in thisPool are greater than requested transaction then take all tokens from this pool
                    if(thisPoolBalance >= _amount){
                        address[] memory clearAddress  = new address[](1);
                        uint256[] memory clearAmount  = new uint256[](1);
                        clearAddress[0] = filteredPools[i];
                        clearAmount[0] = _amount;
                        return (clearAddress, clearAmount);    
                    // otherwise take the remaining tokens form this pool and and adjust amount left to take from other pools                    
                    } else {
                        txAddresses[i] = filteredPools[i];
                        txAmounts[i] = thisPoolBalance;
                        amount = amount.sub(thisPoolBalance);
                    }
                }
            }
        }

        // step 3 - get each pools target token balance as % of  totalTargetsAllPools 
        //          and adjust this based on the pools current variance to its target up if deposit, down if withdrawl
        //          at the same time sum up all of these new targets so that we can calculate them as % of total in next step
        uint256[] memory adjustedTargets  = new uint256[](filteredPools.length);        
        uint256 totalAllAdjustments;
        for (uint256 i = 0; i < filteredPools.length; i++) { 
            IBaseInvestmentPool pool = IBaseInvestmentPool(filteredPools[i]);
            uint256 targetBalance = pool.getTargetAlpBalance(_token);   
            if(targetBalance <= 0){
                adjustedTargets[i] = 0;
            } else {        
                (uint256 variance, bool isPositive) = pool.getVarianceToTarget(_token, isDeposit);
                if((isPositive && isDeposit) || !isPositive && !isDeposit){
                    adjustedTargets[i] = targetBalance.div(totalTargetsAllPools).add(variance);
                } else {
                    uint256 targetBalanceAsPcnt = targetBalance.div(totalTargetsAllPools);
                    if (targetBalanceAsPcnt <= variance) {
                        adjustedTargets[i] = 0;
                    } else {
                        adjustedTargets[i] = targetBalanceAsPcnt.sub(variance);
                    }
                }
            }
            totalAllAdjustments = totalAllAdjustments.add(adjustedTargets[i]);
        }
        require(totalAllAdjustments > 0,"FundManager: Invalid adjustments");

        // step 4 - correct the adjustments as % of total so that final total will be 100% then allocate tokens based on this
        // TO DO create a base fund which holds any tokens that are awaiting allocation then
        // add these tokens to the amount to be allocated before next step
        uint256 tokenPrice = IVaultPriceFeed(priceFeed).getPrice(_token, true, true, false);
        for (uint256 i = 0; i < filteredPools.length; i++) {     
            if(txAmounts[i] != 0){ continue;} // Clearing pool with zero target handled earlier
            uint256 thisPoolsAllocation = amount.mul(adjustedTargets[i].div(totalAllAdjustments));
            if(thisPoolsAllocation.mul(tokenPrice) > MIN_TX_LIMIT){
                txAddresses[i] = filteredPools[i];
                txAmounts[i] = thisPoolsAllocation;                
            } else {
                // TO DO pushTxAddresses[i] = defaultpool;
                // pushTxAmounts[i] = thisPoolsAllocation;  
            }
        }
        return (txAddresses,txAmounts);
    }

    struct TopVariances {
        address pool;
        uint256 target;
        uint256 variance;
        bool isPositive;
    }


    function getTopVariancesToTarget(address _token, address[] memory _filteredPools, bool isDeposit) internal view returns(TopVariances[] memory) {
        TopVariances[] memory poolsToAdjust = new TopVariances[](MAX_POOLS_TO_ADJUST);

        for (uint256 i = 0; i < _filteredPools.length; i++) {
            IBaseInvestmentPool pool = IBaseInvestmentPool(_filteredPools[i]);
            (uint256 variance, bool isPositive) = pool.getVarianceToTarget(_token, isDeposit);
            uint256 targetBalance = pool.getTargetAlpBalance(_token);   
            // Find the index to insert the current pool based on variance
            uint256 insertIndex = 0;
            while (insertIndex < poolsToAdjust.length && variance <= poolsToAdjust[insertIndex].variance) {
                insertIndex++;
            }
            // Shift elements in the array to make space for the new pool
            for (uint256 j = poolsToAdjust.length - 1; j > insertIndex; j--) {
                poolsToAdjust[j] = poolsToAdjust[j - 1];
            }
            // Insert the current pool at the correct index
            poolsToAdjust[insertIndex] = TopVariances(_filteredPools[i], targetBalance, variance, isPositive);
        }
        return poolsToAdjust;
    }
}