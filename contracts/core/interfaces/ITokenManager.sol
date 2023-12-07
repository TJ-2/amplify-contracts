// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ITokenManager {
    function getTokens(address _token, uint256 _amount) external;
    function receiveTokens(address _token, uint256 _amount) external;
    function pullTokens(address _token, uint256 _amount) external returns (bool); 
    function pushTokens(address _token, uint256 _amount) external returns (bool);
    function getTokenBalance(address _token) external view returns(uint256);
    function getTokensPerAlp(address _token, bool _maximise) external view returns(uint256);
    function updateTotalTokenTargets(address _token, uint256 _amount, bool isIncrease) external;
    function getTotalTokenTarget(address _token) external view returns(uint256);
    function getInvestmentPools() external view returns(address[] memory );
    function getFilteredInvestmentPools(address _token) external view returns(address[] memory );
    function isInvestmentPool(address _poolAddress) external view returns(bool);

}