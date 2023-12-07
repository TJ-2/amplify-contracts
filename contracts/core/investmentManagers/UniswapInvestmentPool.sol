// SPDX-License-Identifier: MIT

// This contract provides the interface to a two token investment pool such as a Uniswap v3 liquidity pair
// Single token investments such as Aave lending pools will require a modified version of this contract

pragma solidity 0.6.12;

import "../../libraries/token/IERC20.sol";
import "../../libraries/token/SafeERC20.sol";
import "../../libraries/utils/ReentrancyGuard.sol";
import "../interfaces/IBaseInvestmentPool.sol";
import "../interfaces/IProtocolGov.sol";
import "../interfaces/ITokenManager.sol";
import "../interfaces/IBaseFundManager.sol";

contract UniswapInvestmentPool is IBaseInvestmentPool, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant HUNDRED_PCT= 10000;

    IProtocolGov public protocolGov;

    address public gov;
    address protocolGovAddress;
    address public tokenManagerContract;
    address tokenA;
    address tokenB;
    bool public isInitialized;

    uint256 accEarningsPerTokenA;
    uint256 accEarningsPerTokenB;

    mapping(address => uint256) TargetALPBalances;
    mapping(address => mapping(address => uint256)) fmTargetBalance;
    
    // Used in rewards calcs holds a snapshot of accEarningsPerToken when TargetALPBalances changes fmAddress => snapshot accEarningsPerToken
    mapping(address => uint256) aeptSnapshotA;   // earnings snapshot per fm  token A 
    mapping(address => uint256) aeptSnapshotB;   // earnings snapshot per fm  token B
    mapping(address => mapping(address => uint256)) fmUnclaimedRewards; // fmAddress => token => rewards value

    event TargetTokenBalancesUpdated (address token, uint256 targetChange, bool isIncrease);
    event ProfitsClaimed(address pool, address recipient, address token, uint256 amount);

    constructor() public {
        gov = msg.sender;
    }

    modifier onlyTokenManager() {
        require(msg.sender == tokenManagerContract, "InvestmentPool: Forbidden");
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "InvestmentPool: Forbidden");
        _;
    }

    modifier onlyApprovedFundManager() {
        require(protocolGov.getIsFundManager(msg.sender), "Not an approved fund manager");
        _;
    }

    function initialize(address _protocolGovAddress, address _tokenManager,  address _tokenA, address _tokenB) external onlyGov {
        require(!isInitialized, "Already Initialized");
        require(_tokenA != address(0) && _tokenB != address(0),"InvestmentPool: Invalid token config");
        require(_protocolGovAddress != address(0),"InvestmentPool: Invalid Gov address");
        require(_tokenManager != address(0),"InvestmentPool: Invalid tokenManager address");
        isInitialized = true;
        tokenManagerContract = _tokenManager;
        tokenA = _tokenA;
        tokenB = _tokenB;
        protocolGovAddress = _protocolGovAddress;
        protocolGov = IProtocolGov(protocolGovAddress);        
    }    
    

    // Updates the ALP target holdings for this investment pool
    function setTargetAlpBalance(uint256 _targetChange, bool isIncrease) external override onlyApprovedFundManager nonReentrant {        
        require(_targetChange > 0,"InvestmentPool: invalid target balance");        
        _updateRewards();
        address[] memory poolTokens = _getPoolConfig(); 
        // If there are more than 1 token in this pool then 
        // the _targetChange of ALP will be evenly split across the different tokens in this pool
        require(poolTokens.length > 0, "InvestmentPool: No tokens in the pool");
        uint256 allocationSplit = _targetChange.div(poolTokens.length);
        // cycle through the tokens in the pool and update the ALP targets for each
        for (uint256 i = 0; i < poolTokens.length; i++) {         
            if(isIncrease){
                TargetALPBalances[poolTokens[i]] = TargetALPBalances[poolTokens[i]].add(allocationSplit);
                fmTargetBalance[msg.sender][poolTokens[i]].add(allocationSplit);
                ITokenManager(tokenManagerContract).updateTotalTokenTargets(poolTokens[i], allocationSplit, true);
            } else {
                if(allocationSplit >= TargetALPBalances[poolTokens[i]]) {
                    ITokenManager(tokenManagerContract).updateTotalTokenTargets(poolTokens[i], TargetALPBalances[poolTokens[i]], false);
                    TargetALPBalances[poolTokens[i]] = 0;
                    fmTargetBalance[msg.sender][poolTokens[i]] = 0;                    
                } else {
                    TargetALPBalances[poolTokens[i]] = TargetALPBalances[poolTokens[i]].sub(allocationSplit);
                    ITokenManager(tokenManagerContract).updateTotalTokenTargets(poolTokens[i], allocationSplit, false);
                    if (allocationSplit >= fmTargetBalance[msg.sender][poolTokens[i]]){
                        fmTargetBalance[msg.sender][poolTokens[i]] = 0;
                    } else {
                        fmTargetBalance[msg.sender][poolTokens[i]] = fmTargetBalance[msg.sender][poolTokens[i]].sub(allocationSplit);
                    }
                }
            }  
            emit TargetTokenBalancesUpdated (poolTokens[i], allocationSplit, isIncrease); 
        }     
        
    }

    function updateRewards() external override onlyApprovedFundManager nonReentrant {
        _updateRewards();
    }

    function _updateRewards() private {
        if(TargetALPBalances[tokenA] > 0 && TargetALPBalances[tokenB] >0) {
            // Step 1 - claim all pending rewards from investment pool - two token pool
            (uint256 latestRewardsTokenA, uint256 latestRewardsTokenB) = (1e20,2e20); // _getRewardsFromInvestment(); 
            // TO DO write getRewardsFromInvestment - assume two token pool and remember to unwrap ETH
            
            // step 2 - calculate the earnings per target token since last claim and add to accrued earnings per token accEarningsPerToken
            accEarningsPerTokenA = accEarningsPerTokenA.add(latestRewardsTokenA.div(TargetALPBalances[tokenA]));
            accEarningsPerTokenB = accEarningsPerTokenB.add(latestRewardsTokenB.div(TargetALPBalances[tokenB]));
            // step 4 - calculate the share of rewards for calling FM since last claim
            uint256 shareOfRewardsA = fmTargetBalance[msg.sender][tokenA].mul(accEarningsPerTokenA.sub(aeptSnapshotA[msg.sender]));
            uint256 shareOfRewardsB = fmTargetBalance[msg.sender][tokenB].mul(accEarningsPerTokenB.sub(aeptSnapshotB[msg.sender]));
            // step 3 - pay protocol fees for the FM on this payout and calculate net rewards after fees
            uint256 fmTVL = IBaseFundManager(msg.sender).getFundALPBalance();
            uint256 feeRate = protocolGov.getPerformanceFeeRate(fmTVL);
            address treasuryAddress = protocolGov.getProtocolTreasury();
            uint256 rewardsAfterFeesA = _amountAfterFees(tokenA, treasuryAddress, feeRate,shareOfRewardsA);
            uint256 rewardsAfterFeesB = _amountAfterFees(tokenB, treasuryAddress, feeRate,shareOfRewardsB);
            // step 4 update the unclaimed rewards and the total accumulated rewards over time for the calling FM
            fmUnclaimedRewards[msg.sender][tokenA] = fmUnclaimedRewards[msg.sender][tokenA].add(rewardsAfterFeesA);            
            IBaseFundManager(msg.sender).updateAccRewards(tokenA, rewardsAfterFeesA);
            fmUnclaimedRewards[msg.sender][tokenB] = fmUnclaimedRewards[msg.sender][tokenB].add(rewardsAfterFeesB);
            IBaseFundManager(msg.sender).updateAccRewards(tokenB, rewardsAfterFeesB);
            // step 5 - update snapshot for this FM
            aeptSnapshotA[msg.sender] = accEarningsPerTokenA;
            aeptSnapshotB[msg.sender] = accEarningsPerTokenB;
        }
    }

    function _amountAfterFees(address _token, address _treasuryAddress, uint256 _feeRate, uint256 _rewards) internal returns(uint256) {
        uint256 fee = _rewards.mul(_feeRate).div(HUNDRED_PCT);
        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= fee, "InvestmentPool: Insufficient balance");        
        token.safeTransfer(_treasuryAddress, fee);
        return (_rewards.sub(fee));
    }

    function getTokens(address _token, uint256 _amount) external override onlyTokenManager nonReentrant {
        // TO DO Implement logic to get tokens for this contract from uniswap
        // TO DO If the token is ETH then need to get it differnetly and wrap before sending to tokenManager
        require(_amount > 0, "TokenHolder: Amount must be greater than 0");
        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _amount, "InvestmentPool: Insufficient balance");        
        token.safeTransfer(tokenManagerContract, _amount);
    }

    function sendTokens(address _token, uint256 _amount) external override onlyTokenManager nonReentrant {
        require (IERC20(_token).balanceOf(address(this))>= _amount,"InvestmentPool: Insufficient tokens received");
        // To DO Implement logic to send tokens from this contract to 3rd party investment contract
        //TO DO if token is ETH need to unwrap before sending
        // do nothing for the moment as we are just storing tokens here for the moment
    }

    function _getRewardsFromInvestment() private pure returns(uint256){
        // TO DO write this function 
        // if rewards are for multiple tokens then will need to change the _updateRewards function to allow for this
        return 100;
    }

    function sendRewards(address _token, address _recipient) external override onlyApprovedFundManager nonReentrant {
        uint256 amount = fmUnclaimedRewards[msg.sender][_token];
        if(amount > 0) {
            IERC20 token = IERC20(_token);
            require(token.balanceOf(address(this)) >= amount, "InvestmentPool: Insufficient balance");   
            require(_recipient != address(0), "Invalid recipient address");
            fmUnclaimedRewards[msg.sender][_token] = 0;
            token.safeTransfer(_recipient, amount);   
        }
        emit ProfitsClaimed(address(this), _recipient, _token, amount);
    }

    // Getter functions

    function getGov() external view returns(address) {
        return gov;
    }

    function getPoolConfig() external view override returns(address[] memory){
        return _getPoolConfig();
    }

    function _getPoolConfig() internal view returns(address[] memory){
        address[] memory poolTokens = new address[](2); 
        poolTokens[0] = tokenA;
        poolTokens[1] = tokenB;
        return poolTokens;
    }

    function getTargetAlpBalance(address _token) external view override returns (uint256) {
        return TargetALPBalances[_token];
    }

    function getFmTargetBalance(address _fundManager, address _token) external view returns (uint256) {
        return fmTargetBalance[_fundManager][_token];
    }

    function getFmUnclaimedRewards(address _fundManager, address _token) external view returns (uint256) {
        return fmUnclaimedRewards[_fundManager][_token];
    }


    function getTokenBalance(address _token) external view override returns (uint256) {
        return _getTokenBalance(_token);
    }

    function _getTokenBalance(address _token) internal view returns (uint256) {
        address[] memory poolTokens = _getPoolConfig();
        for (uint256 i = 0; i < poolTokens.length; i++) {  
            if (_token == poolTokens[i] ){
                IERC20 tokenContract = IERC20(_token);
                return tokenContract.balanceOf(address(this));  // TO DO need to get balance from actual investment
            }
        }
        return 0;
    }

    function getVarianceToTarget(address _token, bool _maximise) external view override returns (uint256, bool) {
        uint256 balance = _getTokenBalance(_token);
        // manage the situation where target is zero
        if(TargetALPBalances[_token] <= 0){
            if(balance == 0){
                return (0, true);
            } else {
                return (HUNDRED_PCT, false);  // return large number as target is zero but balance is not so needs to be cleared down
            }
        }
        uint256 TokensPerAlp = ITokenManager(tokenManagerContract).getTokensPerAlp(_token, _maximise);
        uint256 TargetTokenBalance = TargetALPBalances[_token].mul(TokensPerAlp);
        if(balance <= TargetTokenBalance) {
            return ((TargetTokenBalance.sub(balance)).div(TargetTokenBalance), true);
        } else {
            return ((balance.sub(TargetTokenBalance)).div(TargetTokenBalance), false);
        }
    }
}