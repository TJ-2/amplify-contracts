// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBaseInvestmentPool {
    function getTokenBalance(address token) external view returns (uint256);
    function getPoolConfig() external view returns(address[] memory);
    function getTargetAlpBalance(address _token) external view returns (uint256);
    function setTargetAlpBalance(uint256 _targetBalance, bool isIncrease) external;
    function getVarianceToTarget(address _token, bool _maximise) external view returns (uint256, bool);
    function updateRewards() external;
    function getTokens(address token, uint256 amount) external;
    function sendTokens(address token, uint256 amount) external;
    function sendRewards(address _token, address _recipient) external;
}