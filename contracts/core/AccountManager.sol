// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../tokens/interfaces/IWETH.sol";
import "./interfaces/IProtocolGov.sol";
import "./interfaces/IBaseFundManager.sol";
import "./interfaces/ITokenManager.sol";
import "./interfaces/IVault.sol";

contract AccountManager is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;   

    // This contract manages user interactions with the Fund Managers
    // Handles user deposits and withdrawls
    // keeps track of user balances and rewards
    
    IProtocolGov public protocolGov;
    IVault public vault;
    IWETH public WETH;

    address public govContract;
    address public gov;
    address tokenManagerContract;
    address public vaultContract;
    address WETHAddress;

    bool public isInitialized;

    mapping(address => mapping(address => uint256)) userHoldings; // FundManager => User => holding
    mapping(address => mapping(address => mapping(address => uint256))) userUnclaimedRewards; // FundManager => User => token => unclaimed rewards
    mapping(address => mapping(address => mapping(address => uint256))) aepsSnapshot; // FundManager => User => token => snapshot accumulated earnings per share

    constructor() public {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Token:Manager: Forbidden");
        _;
    }

    modifier onlyApprovedFundManager() {
        require(protocolGov.getIsFundManager(msg.sender), "Not an approved fund manager");
        _;
    }

    function initialize(address _govContract, address _tokenManagerContract, address _vaultContract, address _WETHAddress) external onlyGov {
        require(!isInitialized, "Already Initialized");
        isInitialized = true;        
        govContract = _govContract;
        protocolGov = IProtocolGov(govContract);
        tokenManagerContract = _tokenManagerContract;
        vaultContract = _vaultContract;
        vault = IVault(vaultContract);
        WETHAddress = _WETHAddress;
        WETH = IWETH(WETHAddress);
    }
    
    function deposit(address _fundManager, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minAlp) external payable nonReentrant {
        // if fundManager is approved then call the relevant deposit function on the specified fundmanager
        require(protocolGov.getIsFundManager(_fundManager), "Not an approved fund manager");  
        require(_minUsdg > 0,"AccountManager: minUsdg must be > 0");
        require(_minUsdg > 0,"AccountManager: minAlp must be > 0");
        if(msg.value > 0){ // if ETH Deposit then tokens need to be wrapped first
            _token = WETHAddress;
            _amount = msg.value;
            WETH.deposit{value: _amount}();
            WETH.transfer(_fundManager, _amount);
        } else { // Other token deposit
            require(vault.whitelistedTokens(_token),"AccountManager: Token not approved");
            require(_amount > 0,"AccountManager: Amount must be greater than 0");
            IERC20 token = IERC20(_token);
            token.safeTransferFrom(msg.sender, _fundManager, _amount);
        }
        uint256 amountInAlp = IBaseFundManager(_fundManager).deposit(_token, msg.sender, _amount, _minUsdg, _minAlp);      
        // update the user balance for specified fundManager
        userHoldings[_fundManager][msg.sender] = userHoldings[_fundManager][msg.sender].add(amountInAlp);  
    }


    function withdraw(address _fundManager, address _token, uint256 _amount, uint256 _minOut) external  nonReentrant { 
        require(protocolGov.getIsFundManager(_fundManager), "Not an approved fund manager");  
        require(_amount > 0,"AccountManager: Amount must be greater than 0");
        require(_minOut > 0,"FundManager: minOut must be > 0");
        uint256 TokensPerAlp = ITokenManager(tokenManagerContract).getTokensPerAlp(_token, false);
        uint256 amountInAlp = _amount.div(TokensPerAlp);
        require(userHoldings[_fundManager][msg.sender] >= amountInAlp, "AccountManager: Insufficient user balance");
        require(IBaseFundManager(_fundManager).getFundALPBalance() >= amountInAlp, "AccountManager: Insufficient fund manager balance");
        userHoldings[_fundManager][msg.sender] = userHoldings[_fundManager][msg.sender].sub(amountInAlp);
        require(IBaseFundManager(_fundManager).withdraw(_token, _amount, _minOut,  msg.sender) == amountInAlp,"AccountManager: mismatch");
    }

    function claimProfits(address _fundManager) external nonReentrant {
        require(protocolGov.getIsFundManager(_fundManager),"AccounManager: Not an approved fund manager");
        IBaseFundManager(_fundManager).claimProfits(msg.sender);
    }

    function updateUserRewards(address _user, address _token, uint256 _amount) external onlyApprovedFundManager {
        require(protocolGov.getIsFundManager(msg.sender),"Account Manager: Not an approved fund manager");
        userUnclaimedRewards[msg.sender][_user][_token]= userUnclaimedRewards[msg.sender][_user][_token].add(_amount);
    }

    function clearUserRewards(address _user, address _token) external onlyApprovedFundManager{
        require(protocolGov.getIsFundManager(msg.sender),"Account Manager: Not an approved fund manager");
        userUnclaimedRewards[msg.sender][_user][_token]= 0;
    }
 
    function updateUserAepsSnapshot(address _user, address _token, uint256 _value) external onlyApprovedFundManager {
        require(protocolGov.getIsFundManager(msg.sender),"Account Manager: Not an approved fund manager");
        userUnclaimedRewards[msg.sender][_user][_token]= _value;
    }

    // getter functions

    function getUserHoldings(address _fundManager, address _user) external view returns(uint256) {
        return userHoldings[_fundManager][_user];
    }

    function getUserUnclaimedRewards(address _fundManager, address _user, address _token) external view returns(uint256) {
        return userUnclaimedRewards[_fundManager][_user][_token];
    }

    function getUserAepsSnapshot(address _fundManager, address _user, address _token) external view returns(uint256) {
        return aepsSnapshot[_fundManager][_user][_token];
    }

    function getGov() external view returns(address) {
        return gov;
    }
}