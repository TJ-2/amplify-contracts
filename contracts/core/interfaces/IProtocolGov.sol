// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IProtocolGov {
    function updateAlpWeightings() external;
    function getIsFundManager(address _fundmanager) external view returns(bool);
    function getAprovedFundManagers() external view returns(address[] memory);
    function getPerformanceFeeRate(uint256 fmTVL) external pure returns(uint256);
    function getProtocolTreasury() external view returns(address);
}