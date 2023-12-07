// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IBaseInvestmentPool.sol";
import "./interfaces/IInvestmentLogic.sol";
import "./interfaces/IGlpManager.sol";
import "./interfaces/IVaultPriceFeed.sol";

contract TokenManager is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;   

    IVault public vault;
    IGlpManager public glpManager;
    IInvestmentLogic public investmentLogic;    
    
    address public vaultContract;
    address public investmentLogicContract;
    address public gov;
    address public admin;
    address public priceFeed;
    address public alp;
    address public glpManagerContract;
    bool public isInitialized;
    bool private locked;

    mapping(address => uint256) public tokenBalances;   
    mapping(address => uint256) public totalTokenTargets; 
    mapping(address => uint256) public reservedBalances;    
    mapping(address => IBaseInvestmentPool) public investmentPools;
    address[] public investmentPoolKeys; 

    event RenounceGovernance();
    event RenounceAdmin();
    event TokenBalanceUpdated(address tokenAddress, uint256 balance);
    event TokensSent (address token, address pool, uint256 amount);
    event TokensReceived (address token, address pool, uint256 amount);

    constructor() public {
        gov = msg.sender;
        admin = msg.sender;
    }

    modifier lock() {
        require(!locked, "Contract is locked");
        locked = true;
        _;
        locked = false;
    }
    modifier onlyVault() {
        require(msg.sender == vaultContract, "Token:Manager: Forbidden");
        _;    }

    modifier onlyGov() {
        require(msg.sender == gov, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyApprovedInvestmentPools() {
        require(_isInvestmentPool(msg.sender), "Token:Manager: Not approved investment pool");
        _;
    }



    //Configuration functions

    function initialize(address _vaultContract, address _investmentLogicContract, address _glpManagerContract, address _priceFeed) external onlyGov {
        require(!isInitialized, "Already Initialized");
        require(_vaultContract != address(0),"TokenManager: invalid vault contract address");
        require(_investmentLogicContract != address(0),"TokenManager: invalid investmentLogicContract address");
        require(_glpManagerContract != address(0),"TokenManager: invalid glpManagerContract address");
        require(_priceFeed != address(0),"TokenManager: invalid priceFeed address");
        isInitialized = true;
        vaultContract = _vaultContract;
        investmentLogicContract = _investmentLogicContract;
        investmentLogic = IInvestmentLogic(investmentLogicContract);
        vault = IVault(vaultContract);
        glpManagerContract = _glpManagerContract;
        glpManager = IGlpManager(glpManagerContract);
        priceFeed = _priceFeed;
    }

    // once  the protocol is stable this enables contracts to be locked down
    function renounceGovernance() external onlyGov {
        gov = address(0);
        emit RenounceGovernance();
    }

    // admin can only add new investment pools
    function setAdmin(address _newAdminAddress) external onlyAdmin {
        require(_newAdminAddress != address(0),"Invalid address");
        admin = _newAdminAddress;
    }

    // once fund config is finalised this enables investment config lock down
    function renounceAdmin() external onlyAdmin {
        admin = address(0);
        emit RenounceAdmin();
    }

    function updateVaultAddress(address _contractAddress) external onlyGov {
        require(_contractAddress != address(0),"Invalid contract address");
        vaultContract = _contractAddress;
        vault = IVault(vaultContract);
    }

    function updateGlpManagerContract(address _glpManagerContract) external onlyGov {
        require(_glpManagerContract != address(0),"Invalid contract address");
        glpManagerContract = _glpManagerContract;
        glpManager = IGlpManager(glpManagerContract);
    }

    function updateInvestmentLogicContract(address _investmentLogicContract) external onlyGov {
        require(_investmentLogicContract != address(0),"Invalid contract address");
        investmentLogicContract = _investmentLogicContract;
        investmentLogic = IInvestmentLogic(investmentLogicContract);
    }

    function updatePriceFeed(address _priceFeed) external onlyGov {
        require(_priceFeed != address(0),"Invalid contract address");
        priceFeed = _priceFeed;
    }

    function addInvestmentPool(address _contractAddress) external onlyAdmin {
        require(_contractAddress != address(0),"Invalid contract address");
        investmentPools[_contractAddress] = IBaseInvestmentPool(_contractAddress);
        investmentPoolKeys.push(_contractAddress);
    }

   // Core functions

    // Recieves tokens from vault and deploys them to InvestmentPools based on allocation logic
    function receiveTokens(address _token, uint256 _amount) external nonReentrant onlyVault {
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        require(contractBalance.sub(reservedBalances[_token]) >= _amount, "TokenManager: Insufficient tokens received");
        require(_pushTokens(_token, _amount),"TokenManager: Invalid token allocation");
        tokenBalances[_token] = tokenBalances[_token].add(_amount);
    }

    // Get an amount of _token from the InvestmentPools based on allocation logic and send them to Vault contract
    function getTokens(address _token, uint256 _amount) external nonReentrant onlyVault {
        // update the total token balance across protocol as it may have moved since last external interactions eg swaps on Uniswap
        uint256 tokenBalance = getPoolsTokenBalance(_token);
        require(_amount > 0 && _amount <= tokenBalance,"TokenManager: Invalid token amount");
        require(_pullTokens(_token, _amount),"TokenManager: Invalid transfer");  // Pulls tokens from investment pools to this contract
        tokenBalances[_token] = tokenBalances[_token].sub(_amount);
        reservedBalances[_token] = reservedBalances[_token].sub(_amount); // because _pullTokens sets reservedBalance to contract holding which includes _amount to be sent to vault
        IERC20(_token).safeTransfer(vaultContract, _amount);        
    }
    

    function pullTokens(address _token, uint256 _amount) external nonReentrant onlyVault returns (bool) {
        return _pullTokens(_token, _amount);
    }

    function pushTokens(address _token, uint256 _amount) external nonReentrant onlyVault returns (bool) {
        return _pushTokens(_token, _amount);
    }

    function _pullTokens(address _token, uint256 _amount) private returns (bool) {
        IERC20 tokenContract = IERC20(_token);
        uint256 startBalance = tokenContract.balanceOf(address(this));
        // Step 1 - Decide where to get the tokens based on current pool targets and allocations
        // the result is an array of pool addresses to get the tokens from and a corresponding amount for each pool
        (address[] memory poolTxAddresses, uint256[] memory poolTxAmounts) = investmentLogic.getPoolTransactions(_token, _amount,false);
        require(poolTxAddresses.length == poolTxAmounts.length,"TokenManager: Tx length mismatch");
        
        // Step 2 - work through the poolTransactions in turn and get the tokens from the pool managers
        for (uint256 i = 0; i < poolTxAddresses.length; i++) { 
            IBaseInvestmentPool nextPool = investmentPools[poolTxAddresses[i]];
            nextPool.getTokens(_token, poolTxAmounts[i]);
            emit TokensReceived (_token, poolTxAddresses[i], poolTxAmounts[i]);
        }
        uint256 endBalance = tokenContract.balanceOf(address(this));
        reservedBalances[_token] = endBalance;
        bool tokensRecievedOk = _amount == endBalance.sub(startBalance);
        return tokensRecievedOk;
    }

        function _pushTokens(address _token, uint256 _amount) private returns (bool) {
        IERC20 tokenContract = IERC20(_token);
        uint256 startBalance = tokenContract.balanceOf(address(this));
        require(startBalance >= _amount,"Insufficient balance");
        // Step 1 - Decide where to send the tokens based on current pool targets and allocations
        // the result is an array of pool addresses to send the tokens to and a corresponding amount for each pool
        (address[] memory poolTxAddresses, uint256[] memory poolTxAmounts) = investmentLogic.getPoolTransactions(_token, _amount,true);
        require(poolTxAddresses.length == poolTxAmounts.length,"TokenManager: Tx length mismatch");

        // Step 2 - work through the poolTransactions in turn and send the tokens to the pool managers
        for (uint256 i = 0; i < poolTxAddresses.length; i++) { 
            IBaseInvestmentPool nextPool = investmentPools[poolTxAddresses[i]];
            IERC20(_token).safeTransfer(poolTxAddresses[i], poolTxAmounts[i]);  // send the tokens to the poolManager
            nextPool.sendTokens(_token, poolTxAmounts[i]);  //  get the poolManager to allocate them to the pool
            emit TokensSent (_token, poolTxAddresses[i], poolTxAmounts[i]);
        }
        uint256 endBalance = tokenContract.balanceOf(address(this));
        reservedBalances[_token] = endBalance;
        bool tokensSentOk = _amount == startBalance.sub(endBalance);  // TO DO check what happens if allocation logic doesn't allocate full amount
        return tokensSentOk;
    }

   function getPoolsTokenBalance(address _token) internal lock returns (uint256){      
        uint256 balance;
        address[] memory filteredPools = _getFilteredInvestmentPools(_token);   // get all of the pools that use this token
        balance = IERC20(_token).balanceOf(address(this));                      // get the balance of tokens held in reserve on this contract
        // loop through each pool that use this token
        for (uint256 i = 0; i < filteredPools.length; i++) { 
            address poolAddress = filteredPools[i];
            IBaseInvestmentPool pool = investmentPools[poolAddress];
            balance = balance.add(pool.getTokenBalance(_token));   // increment the balance with the amount held in each investment pool             
        }
        tokenBalances[_token] = balance;
        emit TokenBalanceUpdated(_token, balance);
        return balance;
    }

    function getTokenBalances() internal lock {      
        uint256 balance;
        uint256 numOfTokens = vault.allWhitelistedTokensLength();
        // Loop through each whitelistedasset
        for (uint256 j = 0; j < numOfTokens; j++) {   
            address tokenAddress = vault.allWhitelistedTokens(j); 
            balance = IERC20(tokenAddress).balanceOf(address(this)); // get the balance of tokens held in reserve on this contract
            // loop through each InvestmetPool
            for (uint256 i = 0; i < investmentPoolKeys.length; i++) { 
                address poolAddress = investmentPoolKeys[i];
                IBaseInvestmentPool pool = investmentPools[poolAddress];
                balance = balance.add(pool.getTokenBalance(tokenAddress));   // increment the balance with the amount held in each investment pool             
            }
            tokenBalances[tokenAddress] = balance;
            emit TokenBalanceUpdated(tokenAddress, balance);
        }
    }

    function updateTotalTokenTargets(address _token, uint256 _amount, bool isIncrease) external onlyApprovedInvestmentPools {
        if(isIncrease){
            totalTokenTargets[_token] = totalTokenTargets[_token].add(_amount);
        } else {
            if(totalTokenTargets[_token] >_amount){
                totalTokenTargets[_token] = totalTokenTargets[_token].sub(_amount);
            } else {
                totalTokenTargets[_token] = 0;
            }
        }
    }

    // getter functions 

    // gets latest recorded token balances 
    // this function does not update the balances based on latest balances held by 3rd party investment pools
    // CAUTION if using for anything but display purposes
    // TO DO check how this is used by vault contract
    function getTokenBalance(address _token) external view onlyVault returns(uint256) {
        return tokenBalances[_token];
    } 

    function getTotalTokenTarget(address _token) external view returns(uint256) {
        return totalTokenTargets[_token];
    } 

    function getTokensPerAlp(address _token, bool _maximise) external view returns(uint256){
        // get AUM and totalSupply of ALP and calc price of aum
        uint256 aumInUsdg = glpManager.getAumInUsdg(_maximise);
        uint256 glpSupply = IERC20(alp).totalSupply();
        uint256 glpPrice = aumInUsdg.div(glpSupply);
        uint256 tokenPrice = IVaultPriceFeed(priceFeed).getPrice(_token, _maximise, true, _maximise);
        require(tokenPrice > 0,"TokenManager: Invalid token price");
        return glpPrice.div(tokenPrice);
    }

    function getInvestmentPools() external view returns(address[] memory ){
        return investmentPoolKeys;
    }

    function getFilteredInvestmentPools(address _token) external view returns(address[] memory ){
        return _getFilteredInvestmentPools(_token);
    }

    function _getFilteredInvestmentPools(address _token) internal view returns(address[] memory ){
        uint256 count = 0;
        address[] memory filteredPools = new address[](investmentPoolKeys.length);
        address[] memory poolConfig;
        for (uint256 i = 0; i < investmentPoolKeys.length; i++) { 
            IBaseInvestmentPool pool = investmentPools[investmentPoolKeys[i]];
            poolConfig = pool.getPoolConfig();
            if( poolConfig[0] == _token || poolConfig[1] == _token) {
                filteredPools[count] = investmentPoolKeys[i];
                count++;
            }
        }
        assembly {mstore(filteredPools, count)} // resize the array
        return filteredPools;
    }

    function isInvestmentPool(address _poolAddress) external view returns(bool){
        return _isInvestmentPool(_poolAddress);
    }

    function _isInvestmentPool(address _poolAddress) internal view returns(bool){
        if(investmentPools[_poolAddress] != IBaseInvestmentPool(address(0))) {
            return true;
        }
        return false;
    }

}