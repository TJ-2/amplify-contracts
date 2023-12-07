// SPDX-License-Identifier: MIT

// Takes input from approved FundManagers and uses these to 
// algorithmically control the configuration of the protocol

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../peripherals/interfaces/ITimelock.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IBaseInvestmentPool.sol";
import "./interfaces/IBaseFundManager.sol";
import "../staking/interfaces/IRewardTracker.sol";


contract ProtocolGov is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;   

    uint256 public constant HUNDRED_PCT= 10000;
    uint256 public constant MIN_PERFORMANCE_FEE_PCT= 10;  // 0.1%
    uint256 public constant MAX_PERFORMANCE_FEE_PCT= 800; // 8%
    uint256 public constant PERFORMANCE_TVL_THRESHOLD = 1e24;  // $1,000,000

    bool public isInitialized;

    uint256 public minPerformanceFeePcnt;
    uint256 public maxPerformanceFeePcnt;
    uint256 public performanceTvlThreshold;

    address public gov;
    address public protocolTreasury;
    address public timelockContract;
    address public vaultContract;
    address public stakedGlpTracker;

    ITimelock public timelock;
    IVault public vault; 

    mapping(address => bool) isFundManager;
    address [] FundManagers;
    // FundManager Address => Token Address => token weighting
    mapping(address => mapping(address => uint256)) fundTokenWeightings;
    // FundManager address => total USD balance of all tokens - used in rebalancing fund weights
    mapping(address => uint256) fundCurrentBalance; 

    mapping(address => uint256) newTokenWeightings;
    
    event OwnershipTransferred(address _from, address _to);
    event FundManagerAdded(address _fundmanager);
    event FundManagerRemoved(address _fundmanager);
    event AlpWeightingUpdated (address token, uint256 newWeighting, uint256 minProfitBps, uint256 maxUsdgAmount, uint256 bufferAmount, uint256 usdgAmount);

    constructor() public {
        gov = msg.sender;
        minPerformanceFeePcnt = MIN_PERFORMANCE_FEE_PCT;
        maxPerformanceFeePcnt = MAX_PERFORMANCE_FEE_PCT;
        performanceTvlThreshold = PERFORMANCE_TVL_THRESHOLD;
    }
   
    modifier onlyGov() {
        require(msg.sender == gov, "ProtocolGov: Forbidden");
        _;
    }

    modifier onlyApprovedFundManagers() {
        require(isFundManager[msg.sender], "ProtocolGov: Forbidden");
        _;
    }

    function initialize(address _protocolTreasury, address _timelockContract, address _vaultContract, address _stakedGlpTracker) external onlyGov {
        require(!isInitialized, "ProtocolGov: Already Initialized");
        isInitialized = true;
        timelockContract = _timelockContract;
        timelock = ITimelock(timelockContract);
        vaultContract = _vaultContract;
        vault = IVault(vaultContract);
        stakedGlpTracker = _stakedGlpTracker;
        protocolTreasury = _protocolTreasury;
    }
     
    function renounceOwnership() public virtual onlyGov {
        emit OwnershipTransferred(gov, address(0));
        gov = address(0);
    }

    function setPerformanceFeeStructure(uint256 _minPerformanceFeePcnt,
                                        uint256 _maxPerformanceFeePcnt,
                                        uint256 _performanceTvlThreshold) external onlyGov {
        require(_minPerformanceFeePcnt >= MIN_PERFORMANCE_FEE_PCT,"ProtocolGov: Invalid min fee");
        require(_maxPerformanceFeePcnt <= MAX_PERFORMANCE_FEE_PCT,"ProtocolGov: Invalid max fee");
        require(_maxPerformanceFeePcnt >=_minPerformanceFeePcnt,"ProtocolGov: Invalid fee structure");
        require(_performanceTvlThreshold > 0,"ProtocolGov: Invalid performance threshold");        
        minPerformanceFeePcnt = _minPerformanceFeePcnt;
        maxPerformanceFeePcnt = _maxPerformanceFeePcnt;
        performanceTvlThreshold = _performanceTvlThreshold;
    }

    function setProtocolTreasury(address _protocolTreasury) external onlyGov {
        protocolTreasury = _protocolTreasury;
    }
    
    function approveFundManager(address _fundmanager) external onlyGov {
        require(_fundmanager != address(0),"ProtocolGov: Invalid address");
        isFundManager[_fundmanager] = true;
        FundManagers.push(_fundmanager);
        emit FundManagerAdded(_fundmanager);
    }

    function removeFundManager(address _fundmanager) external onlyGov {
        require (isFundManager[_fundmanager],"ProtocolGov: Not a fund manager");
        // Remove the fund manager from the list
        for (uint256 i = 0; i < FundManagers.length; i++) {
            if (FundManagers[i] == _fundmanager) {
                // Move the last element to the current position and then reduce the array length
                FundManagers[i] = FundManagers[FundManagers.length - 1];
                FundManagers.pop();
                break; 
            }
        }
        isFundManager[_fundmanager] = false;
        emit FundManagerRemoved(_fundmanager);
    }

    // TO DO review when this function should be called.  Currently only when weightings changed but should be when balance changes
    // maybe use a tvl check function to see if deviation merits an update
    function updateAlpWeightings() external onlyApprovedFundManagers {
        // get system tvl
        uint256 TotalValueAllFunds = IERC20(stakedGlpTracker).totalSupply();
        // get current ALP balances for each fund manager
        for (uint256 j = 0; j < FundManagers.length; j++) { 
            fundCurrentBalance[FundManagers[j]] = IERC20(stakedGlpTracker).balanceOf(FundManagers[j]);
        }
        // for each token iterate over funds and calculate new weighting based on proportion of tvl from each fund
        uint256 newWeighting;
        for (uint256 i = 0; i < vault.allWhitelistedTokensLength(); i++) {
            newWeighting = 0;
            address token = vault.allWhitelistedTokens(i); 
            for (uint256 j = 0; j < FundManagers.length; j++) {     
                uint256 targetWeight = IBaseFundManager(FundManagers[j]).getTokenWeightings(token);  
                uint weightingThisFund = targetWeight.mul((fundCurrentBalance[FundManagers[j]]).div(TotalValueAllFunds));
                newWeighting = newWeighting.add(weightingThisFund);            
            }
            newTokenWeightings[token] = newWeighting;
            uint256 minProfitBps = vault.minProfitBasisPoints(token);
            uint256 maxUsdgAmount = vault.maxUsdgAmounts(token);
            uint256 bufferAmount = vault.bufferAmounts(token);
            uint256 usdgAmount = vault.usdgAmounts(token);
            timelock.setTokenConfig(vaultContract, token, newWeighting, minProfitBps, maxUsdgAmount, bufferAmount, usdgAmount);
            emit AlpWeightingUpdated (token, newWeighting, minProfitBps, maxUsdgAmount, bufferAmount, usdgAmount);
        }
    }


    // To Do If a token has been delisted from whitelist but is still in fund manager weightings then remaining weightings need to be uplifted
    function _rebalanceFundWeightings (address _fundManager, uint _totalWeightings) private {
        for (uint256 j = 0; j < vault.allWhitelistedTokensLength(); j++) {
            address token = vault.allWhitelistedTokens(j);
            if(!vault.whitelistedTokens(token)) {
                    continue; // ignore tokens that have been delisted
                }
            fundTokenWeightings[_fundManager][token] = _totalWeightings.mul(HUNDRED_PCT).div(_totalWeightings);
        }
    }

    // returns a value between MIN_PERFORMANCE_FEE_PCT and MAX_PERFORMANCE_FEE_PCT depending on fmTVL
    // as fmTVL increases rate reduces from max to min level
    function getPerformanceFeeRate(uint256 fmTVL) external view returns(uint256) {
        if(fmTVL >= performanceTvlThreshold) {
            return 10;
        } else {
            uint256 rate = maxPerformanceFeePcnt.sub(
                (maxPerformanceFeePcnt.sub(minPerformanceFeePcnt)).mul(fmTVL).div(performanceTvlThreshold));
            return rate;
        }
    }

    // getter functions

    function getIsFundManager(address _fundmanager) external view returns(bool) {
        return isFundManager[_fundmanager];
    }

    function getAprovedFundManagers() external view returns(address[] memory) {
        return FundManagers;
    }

    function getProtocolTreasury() external view returns(address) {
        return protocolTreasury;
    }
}