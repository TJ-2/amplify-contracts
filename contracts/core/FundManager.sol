// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../tokens/interfaces/IWETH.sol";
import "./interfaces/IBaseFundManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IBaseInvestmentPool.sol";
import "./interfaces/IProtocolGov.sol";
import "./interfaces/ITokenManager.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "./interfaces/IAccountManager.sol";
import "../staking/interfaces/IRewardRouter.sol";
import "../staking/interfaces/IRewardTracker.sol";


contract FundManager is IBaseFundManager, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;   

    uint256 public constant HUNDRED_PCT= 10000;
    uint256 public constant MIN_TX_LIMIT = 1000000; // $1
    uint256 public constant MAX_MANAGEMENT_FEE = 1000; // 10%
    uint256 public constant MIN_MANAGEMENT_FEE = 1; // 0.001%
    uint256 public constant INITIAL_MANAGEMENT_FEE = 200; // 2%
    uint256 public initializedBlock; // the block when the fund was originally set up
    uint256 public managementFee;   // 10,000 = 100%
    uint256 public totalLifetimeFees;

    IVault public vault;
    IProtocolGov public protocolGov;
    ITokenManager public tokenManager;
    IRewardRouter public rewardRouter;
    IAccountManager public accountManager;
    IWETH public WETH;

    address public vaultContract;
    address public govContract;
    address public tokenManagerContract;
    address public rewardRouterContract;
    address public stakedGlpTracker;
    address public accountManagerContract;
    address public gov;
    address public owner;
    address public fmTreasury;
    address WETHAddress;

    bool public isInitialized;
    
    struct TargetWeighting {
        address tokenAddress;
        uint256 weighting;
    }
    mapping(address => uint256) poolTargetWeightings;  // token address => weighting
    mapping(address => uint256) fundTokenBalance;       // token address => deposit balance

    struct ApprovedInvestment {
        address investmentPoolAddress;
        uint256 allocationPcnt;
    }
    ApprovedInvestment[] ApprovedInvestments;
    mapping(address => bool) isApproveInvestment;
    // token => total accumulated rewards for this token across all investment pools. Used for user rewards management
    mapping(address => uint256) fmAccRewardsPerShare;
    
    event OwnerChanged(address _owner);
    event TreasuryChanged(address _fmTreasury);
    event ApprovedInvestMentsChanged(ApprovedInvestment[] ApprovedInvestments);  
    event Deposit(address token, uint256 amount, address user);
    event Withdraw(address token, uint256 amount, address receiver);
    event ProfitsClaimed(address token, address receiver, uint256 amountAfterFee, uint256 feeAmount);

    constructor() public {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyAccountManager() {
        require(msg.sender == accountManagerContract, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyApprovedInvestmentPools() {
        require(isApproveInvestment[msg.sender], "Token:Manager: Forbidden");
        _;
    }

    function initialize(address _owner, address _fmTreasury, address _vaultContract, address _govContract, 
                        address _tokenManagerContract, address _rewardsRouter, address _stakedGlpTracker, 
                        address _accountManager, address _WETHAddress) external onlyGov {
        require(!isInitialized, "Already Initialized");
        isInitialized = true;
        owner = _owner;
        fmTreasury = _fmTreasury;
        vaultContract = _vaultContract;
        vault = IVault(vaultContract);
        govContract = _govContract;
        protocolGov = IProtocolGov(govContract);
        tokenManagerContract = _tokenManagerContract;
        tokenManager = ITokenManager(tokenManagerContract);
        rewardRouterContract = _rewardsRouter;
        rewardRouter = IRewardRouter(rewardRouterContract);
        stakedGlpTracker = _stakedGlpTracker;
        accountManagerContract = _accountManager;
        accountManager = IAccountManager(accountManagerContract);
        WETHAddress = _WETHAddress;
        WETH = IWETH(WETHAddress);
        managementFee = INITIAL_MANAGEMENT_FEE;
    }

    function transferOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0),"FundManager: Invalid address");
        owner = _newOwner;
        emit OwnerChanged(_newOwner);
    }

    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0),"FundManager: Invalid address");
        fmTreasury = _newTreasury;
        emit TreasuryChanged(fmTreasury);
    }

    function setManagementFee(uint256 newFeeRatePcnt) external onlyOwner {
        require(newFeeRatePcnt >= MIN_MANAGEMENT_FEE,"FundManager: Invalid fee rate");
        require(newFeeRatePcnt <= MAX_MANAGEMENT_FEE,"FundManager: Invalid fee rate");
        managementFee = newFeeRatePcnt;
    }

    // sets the preferred weightings for this fund manager for the multi asset liquidity pool
    // weightings are not guaranteed but are aggregated by the ProtocolGov across all authorized fund managers 
    // TO DO restrict target weight inputs to valid range
    function setTargetALPWeightings(TargetWeighting[] memory TargetWeightings) external onlyOwner nonReentrant() {
        require(TargetWeightings.length <= vault.allWhitelistedTokensLength(),"FundManager: Too many assets");
        uint256 totalAllocations = 0;
        for (uint256 i = 0; i < TargetWeightings.length; i++) { 
            require(vault.whitelistedTokens(TargetWeightings[i].tokenAddress),"FundManager: Asset not approved");
            poolTargetWeightings[TargetWeightings[i].tokenAddress] = TargetWeightings[i].weighting;
            totalAllocations = totalAllocations.add(TargetWeightings[i].weighting);
        }
        require(totalAllocations == HUNDRED_PCT,"FundManager: Invalid allocations");
        // call governance and update vault allocations protocolGov.updateWeightings
        protocolGov.updateAlpWeightings();
    }

    // Defines how assets in this fund are allocated across InvestmentPools
    // eg 60% to UniSwap ETH-USDC LP, 20% Aave, 20% held in reserve
    function setApprovedInvestments(ApprovedInvestment[] memory _approvedInvestments) external onlyOwner {        
        uint256 totalAllocation;
        // loop through ApprovedInvestments, check investmentPoolAddress is valid pool then store
        for (uint256 i = 0; i < _approvedInvestments.length; i++) { 
            require (tokenManager.isInvestmentPool(_approvedInvestments[i].investmentPoolAddress),"FundManager: Not an approved investment pool");            
            require(_approvedInvestments[i].allocationPcnt > 0,"FundManager: allocations must be greater than zero");
            require(fmSupportsPoolTokens(_approvedInvestments[i].investmentPoolAddress),"FM must have non zero weightings for investment pool token(s)");
            totalAllocation = totalAllocation.add(_approvedInvestments[i].allocationPcnt);
            isApproveInvestment[_approvedInvestments[i].investmentPoolAddress] = true;
        }
        require(totalAllocation == HUNDRED_PCT,"FundManager: Allocation must be 100%");
        ApprovedInvestments = _approvedInvestments;      
        emit ApprovedInvestMentsChanged(ApprovedInvestments);  
    }


    function deposit(address _token, address _user, uint256 _amount, uint256 _minUsdg, uint256 _minAlp) 
                        external override nonReentrant onlyAccountManager returns(uint256) {
        // Most of the deposit actions are managed by core code, however target allocations need to be updated before this is invoked
        // update the investment pool targets & rewards allocations
        uint256 amountInAlp = _updatePoolTargets(_token, _amount, true);     
        _updateUserRewards(_token, _user);

        // now call core code for deposit on behalf of this fund manager
        // TO DO probably need to call the approve function first
        require(IERC20(_token).balanceOf(address(this)) >= _amount,"FundManager: Insufficient token balance");
        rewardRouter.mintAndStakeGlp(_token, _amount, _minUsdg, _minAlp);

        emit Deposit(_token, _amount, _user);
        return (amountInAlp);
    }

    function withdraw(address _token, uint256 _amount, uint256 _minOut, address _receiver) 
                        external override nonReentrant onlyAccountManager returns (uint256) {
        // Most of the deposit actions are managed by core code, however target allocations need to be updated before this is invoked        
        require(_receiver != address(0),"FundManager: Invalid receiver address");
        uint256 amountInAlp = _updatePoolTargets(_token, _amount, false);
        _updateUserRewards(_token, _receiver);
        
        // now call core code for withdraw
        if (_token == WETHAddress) {
            // Receive WETH to this contract then unwrap before sending on to _receiver
            uint256 amountOut = rewardRouter.unstakeAndRedeemGlp(_token, _amount, _minOut, address(this));
            WETH.withdraw(amountOut);
            require(address(this).balance >= amountOut, "FundManager: Insufficient balance");
            require(payable (_receiver).send(amountOut),"FundManager: Transfer failed");
        } else {
            rewardRouter.unstakeAndRedeemGlp(_token, _amount, _minOut, _receiver);
        }
        emit Withdraw(_token, _amount, _receiver);
        return (amountInAlp);
    }

    function claimProfits(address _receiver) external override nonReentrant onlyAccountManager { 
        // for each approved investment pool update and claim rewards to FundManager contract
        for (uint256 i = 0; i < ApprovedInvestments.length; i++) {
            IBaseInvestmentPool pool = IBaseInvestmentPool(ApprovedInvestments[i].investmentPoolAddress);
            pool.updateRewards();
            address[] memory tokens = pool.getPoolConfig();
            for (uint256 j = 0; j < tokens.length; j++) {
                pool.sendRewards(tokens[j], address(this));  // claim all unclaimedRewards back to this contract
            }
        }
        // for this user and for each protocol approved token updateUserRewards then pay the user
        uint256 numTokens = vault.allWhitelistedTokensLength();
        for (uint256 i = 0; i < numTokens; i++) {
            address whitelistToken = vault.allWhitelistedTokens(i);
            _updateUserRewards(whitelistToken,_receiver);
            uint256 unclaimedReward = accountManager.getUserUnclaimedRewards(address(this), _receiver, whitelistToken);
            if(unclaimedReward > 0) {
                IERC20 token = IERC20(whitelistToken);
                require(token.balanceOf(address(this)) >= unclaimedReward, "FundManager: Insufficient balance");   
                accountManager.clearUserRewards(_receiver,whitelistToken);                 
                uint256 feeAmount = unclaimedReward.mul(managementFee).div(HUNDRED_PCT);
                uint256 amountAfterFee = unclaimedReward.sub(feeAmount);
                if (whitelistToken == WETHAddress) {
                    // Unwrap ETH before sending
                    WETH.withdraw(unclaimedReward);
                    require(address(this).balance >= feeAmount.add(amountAfterFee), "FundManager: Insufficient balance");
                    require(payable(fmTreasury).send(feeAmount),"FundManager: FM Transfer failed");
                    require(payable(_receiver).send(amountAfterFee),"FundManager: Transfer failed");
                } else {
                    token.safeTransfer(fmTreasury, feeAmount);   
                    token.safeTransfer(_receiver, amountAfterFee);   
                }
                emit ProfitsClaimed(whitelistToken,_receiver,amountAfterFee,feeAmount);
            }
        }      
    }

    function _updateUserRewards(address _token, address _user) private {        
        // Step 1 - Get latest rewards per ALP share of fund for this token
        uint256 accRewardsPerShare = fmAccRewardsPerShare[_token];        
        // step 2 - Get the user ALP balance for this fund
        uint256 currentHolding = accountManager.getUserHoldings(address(this), _user);
        // step 3 calculate the share of rewards of this token for this user
        uint256 shareOfRewards = currentHolding.mul(accRewardsPerShare.sub(accountManager.getUserAepsSnapshot(address(this),_user,_token)));     
        accountManager.updateUserRewards(_user,_token,shareOfRewards);     
        // step 4 - update snapshot for this user
        accountManager.updateUserAepsSnapshot(_user,_token,accRewardsPerShare);
    }


    // helper functions

   function _updatePoolTargets(address _token, uint256 _amount,bool isDeposit) private returns(uint256) {
        // Get this FundManager's  fund allocation ratios and calculate how much of deposited/withdrawn 
        // value goes to each of these pools.  Then calc corresponding value in ALP and updates the targets on the pools
        // ApprovedInvestments[i] includes struct of investmentPoolAddress and allocationPcnt;
        uint256 amountInAlp =   _amount.div(tokenManager.getTokensPerAlp(_token, isDeposit));
        for (uint256 i = 0; i < ApprovedInvestments.length; i++) { 
            IBaseInvestmentPool pool = IBaseInvestmentPool(ApprovedInvestments[i].investmentPoolAddress);
            uint256 targetChange = ApprovedInvestments[i].allocationPcnt.mul(amountInAlp).div(HUNDRED_PCT);
            pool.setTargetAlpBalance(targetChange, isDeposit);
        }    
        return(amountInAlp);
    }


    function fmSupportsPoolTokens(address investmentPool) private view returns(bool) {
        address[] memory tokens = IBaseInvestmentPool(investmentPool).getPoolConfig();
        for (uint256 i = 0; i < tokens.length; i++) {
            if(poolTargetWeightings[tokens[i]] <= 0 ){ 
                return false;
            }
        } 
        return true;
    }

    function updateAccRewards(address _token, uint256 _amount) external override onlyApprovedInvestmentPools { 
        uint256 alpBalance = _getFundALPBalance();
        require(alpBalance > 0,"FundManager: Zero Balance");
        fmAccRewardsPerShare[_token] = fmAccRewardsPerShare[_token].add(_amount.div(alpBalance));
    }

    // getter functions

    function getGov() external view returns(address){
        return gov;
    }

    function getOwner() external view returns(address){
        return owner;
    }

    function getFmTreasury() external view returns(address){
        return fmTreasury;
    }

    function getAccountManager() external view returns(address){
        return accountManagerContract;
    }

    
    function getManagementFee() external view returns(uint256){
        return managementFee;
    }

    function getTokenWeightings(address _token) override external view returns (uint256) {
        return poolTargetWeightings[_token];
    }

    function getFundTokenBalance(address _token) override external view returns (uint256) {
        return fundTokenBalance[_token];
    }

    function getApprovedInvestments()  external view returns (address[] memory, uint256[] memory) {
        address[] memory addresses = new address[](ApprovedInvestments.length);
        uint256[] memory allocations = new uint256[](ApprovedInvestments.length);
        for (uint256 i = 0; i < ApprovedInvestments.length; i++) {
            addresses[i] = ApprovedInvestments[i].investmentPoolAddress;
            allocations[i] = ApprovedInvestments[i].allocationPcnt;
        }
        return (addresses,allocations);
    }

    function getFundALPBalance() override external view returns (uint256) {
        return _getFundALPBalance();
    }
    
    function _getFundALPBalance() internal view returns (uint256) {
        return IERC20(stakedGlpTracker).balanceOf(address(this));        
    }

}