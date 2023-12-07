const { deployContract, contractAt, writeTmpAddresses, sendTxn } = require("../shared/helpers")

async function main() {
    const tokenManager = await deployContract("TokenManager", [4], "TokenManager")

    const signers = [
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // Dovey
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // G
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // Han Wen
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // Krunal Amin
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10", // xhiroz
        "0xCCE4614aDB19bc9e2296D5767Cad47d7b70BBd10" // Bybit Security Team
    ]

    await sendTxn(tokenManager.initialize(signers), "tokenManager.initialize")
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })