// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IBaseFundManager {
    function getTokenWeightings(address _token) external view returns (uint256);
    function getFundTokenBalance(address _token) external view returns (uint256);
    function getFundALPBalance()  external view returns (uint256);
    function deposit(address _token, address _user, uint256 _amount, uint256 _minUsdg, uint256 _minAlp) external returns(uint256);
    function withdraw(address _token, uint256 _amount, uint256 _minOut, address _receiver) external returns(uint256);
    function claimProfits(address _investmentPool) external;
    function updateAccRewards(address _token, uint256 _amount) external;

}