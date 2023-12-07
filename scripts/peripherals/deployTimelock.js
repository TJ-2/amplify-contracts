const { deployContract, contractAt, sendTxn, getFrameSigner } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")

const network = (process.env.HARDHAT_NETWORK || 'mainnet');

async function getArbValues() {
    const vault = await contractAt("Vault", "0x263F1898ce022e1372971343aa90ad5F57151F67")
    const tokenManager = { address: "0xddDc546e07f1374A07b270b7d863371e575EA96A" }
    const glpManager = { address: "0x321F653eED006AD1C29D174e17d96351BDe22649" }

    const positionRouter = { address: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868" }
    const positionManager = { address: "0x75E42e6f01baf1D6022bEa862A28774a9f8a4A0C" }
    const gmx = { address: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a" }

    return { vault, tokenManager, glpManager, positionRouter, positionManager, gmx }
}

async function getTelosTestnetValues() {
    const vault = await contractAt("Vault", "0x263F1898ce022e1372971343aa90ad5F57151F67")
    const tokenManager = { address: "0x6CB5ACb7c8fF95B9f10F1De41578BEA86fE1D40B" }
    const glpManager = { address: "0x8Ec18753afC1Dc1a349ED760856e62fe224E2fE0" }

    // const positionRouter = { address: "0xffF6D276Bc37c61A23f06410Dce4A400f66420f8" }
    // const positionManager = { address: "0xA21B83E579f4315951bA658654c371520BDcB866" }
    const gmx = { address: "0xe55Fef1a65C9EBB609B827c70837367E0AfcE8b3" }

    return { vault, tokenManager, glpManager, gmx }
}

async function getValues() {
    if (network === "arbitrum") {
        return getArbValues()
    }

    if (network === "avax") {
        return getAvaxValues()
    }

    if (network === "telos_testnet") {
        return getTelosTestnetValues()
    }

    if (network === "telos_mainnet") {
        return getTelosMainnetValues()
    }
}

async function main() {
    const signer = await getFrameSigner()

    const admin = "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10"
    const buffer = 24 * 60 * 60
    const maxTokenSupply = expandDecimals("13250000", 18)

    const { vault, tokenManager, glpManager, positionRouter, positionManager, gmx } = await getValues()
    const mintReceiver = tokenManager

    const timelock = await deployContract("Timelock", [
        admin,
        buffer,
        tokenManager.address,
        mintReceiver.address,
        glpManager.address,
        maxTokenSupply,
        10, // marginFeeBasisPoints 0.1%
        500 // maxMarginFeeBasisPoints 5%
    ], "Timelock")

    const deployedTimelock = await contractAt("Timelock", timelock.address, signer)

    await sendTxn(deployedTimelock.setShouldToggleIsLeverageEnabled(true), "deployedTimelock.setShouldToggleIsLeverageEnabled(true)")
        // await sendTxn(deployedTimelock.setContractHandler(positionRouter.address, true), "deployedTimelock.setContractHandler(positionRouter)")
        // await sendTxn(deployedTimelock.setContractHandler(positionManager.address, true), "deployedTimelock.setContractHandler(positionManager)")

    // // update gov of vault
    // const vaultGov = await contractAt("Timelock", await vault.gov(), signer)

    // await sendTxn(vaultGov.signalSetGov(vault.address, deployedTimelock.address), "vaultGov.signalSetGov")
    // await sendTxn(deployedTimelock.signalSetGov(vault.address, vaultGov.address), "deployedTimelock.signalSetGov(vault)")

    const signers = [
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // coinflipcanada
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // G
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // kr
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // quat
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10" // xhiroz
    ]

    for (let i = 0; i < signers.length; i++) {
        const signer = signers[i]
        await sendTxn(deployedTimelock.setContractHandler(signer, true), `deployedTimelock.setContractHandler(${signer})`)
    }

    const keepers = [
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10" // X
    ]

    for (let i = 0; i < keepers.length; i++) {
        const keeper = keepers[i]
        await sendTxn(deployedTimelock.setKeeper(keeper, true), `deployedTimelock.setKeeper(${keeper})`)
    }

    await sendTxn(deployedTimelock.signalApprove(gmx.address, admin, "1000000000000000000"), "deployedTimelock.signalApprove")
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })