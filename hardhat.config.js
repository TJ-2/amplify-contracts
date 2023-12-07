require("@nomiclabs/hardhat-waffle")
require("@nomiclabs/hardhat-etherscan")
require("hardhat-contract-sizer")
require('@typechain/hardhat')
// require("hardhat-gas-reporter");

// require('dotenv').config({ path: __dirname + '/.env' })


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
    const accounts = await ethers.getSigners()

    for (const account of accounts) {
        console.info(account.address)
    }
})

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    networks: {
        localhost: {
            timeout: 120000
        },
        hardhat: {
            allowUnlimitedContractSize: true
        },

        telos_testnet: {
            url: "https://testnet.telos.net/evm",
            gas: 10000000,
            deploy: ["./scripts/access/"],
            chainId: 41,
            accounts: ['0x6110107ee5376c20acadfe82498b4ba93c9fd44a62156e20cfe4563326fd7388']
        },
        telos_mainnet: {
            url: "https://mainnet.telos.net/evm",
            gasPrice: 50000000000,
            deploy: ["./scripts/access/"],
            chainId: 40,
            accounts: ["0x6110107ee5376c20acadfe82498b4ba93c9fd44a62156e20cfe4563326fd7388"]
        }
    },
    solidity: {
        version: "0.6.12",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1
            }
        }
    },
    typechain: {
        outDir: "typechain",
        target: "ethers-v5",
    },
}