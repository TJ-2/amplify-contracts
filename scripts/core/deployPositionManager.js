const { getFrameSigner, deployContract, contractAt, sendTxn } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")
const { toUsd } = require("../../test/shared/units")
const { errors } = require("../../test/core/Vault/helpers")

const network = (process.env.HARDHAT_NETWORK || 'mainnet');
const tokens = require('./tokens')[network];

const depositFee = 30 // 0.3%

async function getArbValues(signer) {
    const vault = await contractAt("Vault", "0x489ee077994B6658eAfA855C308275EAd8097C4A", signer)
    const timelock = await contractAt("Timelock", await vault.gov(), signer)
    const router = await contractAt("Router", await vault.router(), signer)
    const shortsTracker = await contractAt("ShortsTracker", "0xf58eEc83Ba28ddd79390B9e90C4d3EbfF1d434da", signer)
    const weth = await contractAt("WETH", tokens.nativeToken.address)
    const orderBook = await contractAt("OrderBook", "0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB")
    const referralStorage = await contractAt("ReferralStorage", "0xe6fab3f0c7199b0d34d7fbe83394fc0e0d06e99d")

    const orderKeepers = [
        { address: "0xd4266F8F82F7405429EE18559e548979D49160F3" },
        { address: "0x2D1545d6deDCE867fca3091F49B29D16B230a6E4" }
    ]
    const liquidators = [
        { address: "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10" }
    ]

    const partnerContracts = []

    return { vault, timelock, router, shortsTracker, weth, depositFee, orderBook, referralStorage, orderKeepers, liquidators, partnerContracts }
}

async function getTelosTestnetValues(signer) {
    const vault = await contractAt("Vault", "0x263F1898ce022e1372971343aa90ad5F57151F67")
    const timelock = await contractAt("Timelock", "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", signer)
    const router = await contractAt("Router", "0xa4B7F1Db1804Ab1e1FCC65078bf9083b3D9d2D78", signer)
    const shortsTracker = await contractAt("ShortsTracker", "0xE61056163A2e21c4Fc6F94aAcFc4Ed035240d2b0", signer)
    const weth = await contractAt("WETH", "0xaE85Bf723A9e74d6c663dd226996AC1b8d075AA9")
    const orderBook = await contractAt("OrderBook", "0x4106e849502D9eE5a1263D2DEBd61fb741c42550")
    const referralStorage = await contractAt("ReferralStorage", "0x1A88768168e2a2D9756660Bc81e4a7f17e5fEA8C")

    const orderKeepers = [
        { address: "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10" },
        { address: "0xA25bc8c1e230a476cB00f2e9c93ffC2D4e163dc5" }
    ]
    const liquidators = [
        { address: "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10" }
    ]

    const partnerContracts = []

    return { vault, timelock, router, shortsTracker, weth, depositFee, orderBook, referralStorage, orderKeepers, liquidators, partnerContracts }
}

async function getValues(signer) {
    if (network === "arbitrum") {
        return getArbValues(signer)
    }

    if (network === "avax") {
        return getAvaxValues(signer)
    }

    if (network === "telos_mainnet") {
        return getTelosMainnetValues(signer)
    }

    if (network === "telos_testnet") {
        return getTelosTestnetValues(signer)
    }
}

async function main() {
    const signer = await getFrameSigner()

    const {
        positionManagerAddress,
        vault,
        timelock,
        router,
        shortsTracker,
        weth,
        depositFee,
        orderBook,
        referralStorage,
        orderKeepers,
        liquidators,
        partnerContracts
    } = await getValues(signer)

    let positionManager
    if (positionManagerAddress) {
        console.log("Using position manager at", positionManagerAddress)
        positionManager = await contractAt("PositionManager", positionManagerAddress)
    } else {
        console.log("Deploying new position manager")
        const positionManagerArgs = [vault.address, router.address, shortsTracker.address, weth.address, depositFee, orderBook.address]
        positionManager = await deployContract("PositionManager", positionManagerArgs)
    }

    // positionManager only reads from referralStorage so it does not need to be set as a handler of referralStorage
    if ((await positionManager.referralStorage()).toLowerCase() != referralStorage.address.toLowerCase()) {
        await sendTxn(positionManager.setReferralStorage(referralStorage.address), "positionManager.setReferralStorage")
    }
    if (await positionManager.shouldValidateIncreaseOrder()) {
        await sendTxn(positionManager.setShouldValidateIncreaseOrder(false), "positionManager.setShouldValidateIncreaseOrder(false)")
    }

    for (let i = 0; i < orderKeepers.length; i++) {
        const orderKeeper = orderKeepers[i]
        if (!(await positionManager.isOrderKeeper(orderKeeper.address))) {
            await sendTxn(positionManager.setOrderKeeper(orderKeeper.address, true), "positionManager.setOrderKeeper(orderKeeper)")
        }
    }

    for (let i = 0; i < liquidators.length; i++) {
        const liquidator = liquidators[i]
        if (!(await positionManager.isLiquidator(liquidator.address))) {
            await sendTxn(positionManager.setLiquidator(liquidator.address, true), "positionManager.setLiquidator(liquidator)")
        }
    }

    if (!(await timelock.isHandler(positionManager.address))) {
        await sendTxn(timelock.setContractHandler(positionManager.address, true), "timelock.setContractHandler(positionManager)")
    }
    if (!(await vault.isLiquidator(positionManager.address))) {
        await sendTxn(timelock.setLiquidator(vault.address, positionManager.address, true), "timelock.setLiquidator(vault, positionManager, true)")
    }
    if (!(await shortsTracker.isHandler(positionManager.address))) {
        await sendTxn(shortsTracker.setHandler(positionManager.address, true), "shortsTracker.setContractHandler(positionManager.address, true)")
    }
    if (!(await router.plugins(positionManager.address))) {
        await sendTxn(router.addPlugin(positionManager.address), "router.addPlugin(positionManager)")
    }

    for (let i = 0; i < partnerContracts.length; i++) {
        const partnerContract = partnerContracts[i]
        if (!(await positionManager.isPartner(partnerContract))) {
            await sendTxn(positionManager.setPartner(partnerContract, false), "positionManager.setPartner(partnerContract)")
        }
    }

    if ((await positionManager.gov()) != (await vault.gov())) {
        await sendTxn(positionManager.setGov(await vault.gov()), "positionManager.setGov")
    }

    console.log("done.")
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })