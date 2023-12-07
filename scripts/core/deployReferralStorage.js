const { getFrameSigner, deployContract, contractAt, sendTxn, readTmpAddresses, writeTmpAddresses } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")
const { toUsd } = require("../../test/shared/units")

const network = (process.env.HARDHAT_NETWORK || 'mainnet');
const tokens = require('./tokens')[network];

async function getArbValues() {
    const positionRouter = await contractAt("PositionRouter", "0x3D6bA331e3D9702C5e8A8d254e5d8a285F223aba")
    const positionManager = await contractAt("PositionManager", "0x87a4088Bd721F83b6c2E5102e2FA47022Cb1c831")

    return { positionRouter, positionManager }
}

async function getTelosTestnetValues() {
    const positionRouter = await contractAt("PositionRouter", "")
    const positionManager = await contractAt("PositionManager", "")

    return { positionRouter, positionManager }
}

async function getValues() {
    if (network === "arbitrum") {
        return getArbValues()
    }

    if (network === "avax") {
        return getAvaxValues()
    }

    if (network === "telos_testnet") {
        return getTelosTestnetValues(signer)
    }

    if (network === "telos_mainnet") {
        return getTelosMainnetValues(signer)
    }
}

async function main() {
    const { positionRouter, positionManager } = await getValues()
        // const referralStorage = await deployContract("ReferralStorage", [])
    const referralStorage = await contractAt("ReferralStorage", await positionRouter.referralStorage())

    // await sendTxn(positionRouter.setReferralStorage(referralStorage.address), "positionRouter.setReferralStorage")
    // await sendTxn(positionManager.setReferralStorage(referralStorage.address), "positionManager.setReferralStorage")

    await sendTxn(referralStorage.setHandler(positionRouter.address, true), "referralStorage.setHandler(positionRouter)")
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })