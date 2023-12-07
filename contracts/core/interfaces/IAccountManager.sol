// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IAccountManager {
    function updateUserRewards(address _user, address _token, uint256 _amount) external;
     function clearUserRewards(address _user, address _token) external;
    function updateUserAepsSnapshot(address _user, address _token, uint256 _value) external;
    function getUserUnclaimedRewards(address _fundManager, address _user, address _token) external view returns(uint256);
    function getUserHoldings(address _fundManager, address _user) external view returns(uint256);
    function getUserAepsSnapshot(address _fundManager, address _user, address _token) external view returns(uint256);
}