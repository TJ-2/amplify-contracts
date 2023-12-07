const { deployContract, contractAt, sendTxn } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")
const { toUsd } = require("../../test/shared/units")
const { errors } = require("../../test/core/Vault/helpers")

const network = (process.env.HARDHAT_NETWORK || 'mainnet');
const tokens = require('./tokens')[network];

async function main() {
    const vault = await contractAt("Vault", "0x263F1898ce022e1372971343aa90ad5F57151F67")
    const orderBook = await contractAt("OrderBook", "0x4106e849502D9eE5a1263D2DEBd61fb741c42550")
    await deployContract("OrderExecutor", [vault.address, orderBook.address])
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })