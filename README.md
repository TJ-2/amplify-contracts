# Amplify Contracts
Timothy Judge | ECM3175

![alt text](https://github.com/TJ-2/images/blob/main/Screenshot%202023-12-07%20at%2016.26.10.png)


The diagram above shows the interaction between the different smart contracts that together make up the Amplify protocol. Aside from “Core GMX Code” all other smart contracts are unique to Amplify. 

## GMX Core: 
Amplify uses GMXs open source code [4] as a template for the protocol's basic functionality. This code is published under an MIT Licence, a permissive open-source license that allows developers to use, modify, and distribute the software for both commercial and non-commercial purposes, thus enabling Amplify to build on-top of the existing smart-contract framework. 

## AccountManager.sol: 
The account manager is the main contract that Liquidity Providers (LPs)  interact with. This contract provides a few convenience functions for depositing and withdrawing assets with FundManagers. Assets can be deposited and withdrawn by LPs at any time as long as it’s not being reserved for an open trade.  This contract also enables LPs to claim their rewards for providing liquidity on the platform via the “claimProfit” function.

## FundManager.sol  
Whitelisted Fund Managers are able to interact with the FundManager contract to customize their assets allocation. Fund Managers are incentivised to maximize the yield generated on the assets as this will encourage more LPs to deposit into their Fund, which will result in more management and performance fees for the Fund Manager. Via the FundManager.sol contract, the FundManager is able to set the target weighting for the ALP multi-asset liquidity pool along with the target weightings of assets deposited on third-party protocols. 

Via the FundManager.sol contract Fund Managers also have the ability to customize fees charged on their funds. Higher fees may result in greater revenue for the fund, or potentially result in a reduced number of LPs participating. This trade-off is at the discretion of the Fund Managers, allowing them to make strategic decisions based on their unique circumstances and preferences.

## ProtocolGov.sol: 
ProtocolGov.sol plays a crucial role in enhancing the protocol's upgradability without compromising security or decentralization. This is accomplished through the implementation of a multi-signatory contract, necessitating approval from multiple parties for upgrades to be executed. Additionally, ProtocolGov benefits from a 7-day timelock, giving investors a sufficient window to withdraw their funds in case they are uneasy about the upgrade before it takes effect.

## TokenManager.sol: 
Since Amplifiy adds additional complexity to the original GMX code base, the role of TokenManager is to provide structured modularity between the different components. In turn this makes auditing the code easier. TokenManager handles deposits made into the vault.sol contract and redirects the deposits to Investment pools. The exact distribution of tokens sent to Investment pools is determined by InvestmentLogic.sol.

## InvestmentPools.sol: 
InvestmentPools.sol acts as an interface to facilitate deposit and withdrawals to third party protocols.  As each 3rd party protocol will have different deposit and withdrawal logic, we will need unique instances of InvestmentPool.sol to cater for each protocol. 
