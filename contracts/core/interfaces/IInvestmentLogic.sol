// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IInvestmentLogic {
    function getPoolTransactions(address _token, uint256 _amount, bool isDeposit) external view returns(address[] memory, uint256[] memory);
}