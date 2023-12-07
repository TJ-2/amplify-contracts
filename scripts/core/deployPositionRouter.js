const { getFrameSigner, deployContract, contractAt, sendTxn, readTmpAddresses, writeTmpAddresses } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")
const { toUsd } = require("../../test/shared/units")

const network = (process.env.HARDHAT_NETWORK || 'mainnet');
const tokens = require('./tokens')[network];

async function main() {
    const signer = await getFrameSigner()

    const depositFee = "30" // 0.3%
    const minExecutionFee = "100000000000000" // 0.0001 ETH

    const positionRouterArgs = ["0x83Eb78Fe3beEBA9783fDa7f030eaC7A1DA0E5Fff", "0x4e278A6f7C362789cD549113EAe522eFd0207D7D", "0xaE85Bf723A9e74d6c663dd226996AC1b8d075AA9", "0x1D00f3be0aB531CB2DF025e9e8B2520Cf92fD050", depositFee, minExecutionFee]
    // positionRouterArgs: Vault, Router, Weth, shortsTracker
    const positionRouter = await deployContract("PositionRouter", positionRouterArgs)

    // await sendTxn(positionRouter.setReferralStorage(referralStorage.address), "positionRouter.setReferralStorage")
    // await sendTxn(referralStorageGov.signalSetHandler(referralStorage.address, positionRouter.address, true), "referralStorage.signalSetHandler(positionRouter)")
    // await sendTxn(shortsTracker.setHandler(positionRouter.address, true), "shortsTracker.setHandler(positionRouter)")
    // await sendTxn(router.addPlugin(positionRouter.address), "router.addPlugin")
    // await sendTxn(positionRouter.setDelayValues(1, 180, 30 * 60), "positionRouter.setDelayValues")
    // await sendTxn(timelock.setContractHandler(positionRouter.address, true), "timelock.setContractHandler(positionRouter)")
    // await sendTxn(positionRouter.setGov(await vault.gov()), "positionRouter.setGov")
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })