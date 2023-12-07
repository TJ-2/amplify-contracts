const { deployContract, contractAt, sendTxn, writeTmpAddresses } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")

const network = (process.env.HARDHAT_NETWORK || 'mainnet');
const tokens = require('./tokens')[network];

async function main() {
    const { nativeToken } = tokens

    const orderBook = await deployContract("OrderBook", []);

    // Arbitrum mainnet addresses
    await sendTxn(orderBook.initialize(
        "0xa4B7F1Db1804Ab1e1FCC65078bf9083b3D9d2D78", // router
        "0x263F1898ce022e1372971343aa90ad5F57151F67", // vault
        "0xaE85Bf723A9e74d6c663dd226996AC1b8d075AA9", // weth
        "0x860E8131b03AB97b8017F7a2278B27f9991397B2", // usdg
        "10000000000000000", // 0.01 AVAX
        expandDecimals(10, 30) // min purchase token amount usd
    ), "orderBook.initialize");

    writeTmpAddresses({
        orderBook: orderBook.address
    })
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })