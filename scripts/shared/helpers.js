const fs = require('fs')
const path = require('path')
const parse = require('csv-parse')

const network = (process.env.HARDHAT_NETWORK || 'telos_testnet');

const ARBITRUM = 42161
const AVALANCHE = 43114
const TELOS_TESTNET = 41
const TELOS_MAINNET = 40

// const {
//  ARBITRUM_URL,
//   AVAX_URL,
//   ARBITRUM_DEPLOY_KEY,
//  AVAX_DEPLOY_KEY
// } = require("../../env.json")

const providers = {
    // arbitrum: new ethers.providers.JsonRpcProvider(ARBITRUM_URL),
    // avax: new ethers.providers.JsonRpcProvider(AVAX_URL),
    telos_testnet: new ethers.providers.JsonRpcProvider("https://testnet.telos.net/evm"),
    telos_mainnet: new ethers.providers.JsonRpcProvider("https://mainnet.telos.net/evm")
}

const signers = {
    // arbitrum: new ethers.Wallet(ARBITRUM_DEPLOY_KEY).connect(providers.arbitrum),
    // avax: new ethers.Wallet(ARBITRUM_DEPLOY_KEY).connect(providers.avax),
    telos_testnet: new ethers.Wallet("6110107ee5376c20acadfe82498b4ba93c9fd44a62156e20cfe4563326fd7388").connect(providers.telos_testnet),
    telos_mainnet: new ethers.Wallet("6110107ee5376c20acadfe82498b4ba93c9fd44a62156e20cfe4563326fd7388").connect(providers.telos_mainnet)
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

const readCsv = async (file) => {
    records = []
    const parser = fs
        .createReadStream(file)
        .pipe(parse({ columns: true, delimiter: ',' }))
    parser.on('error', function (err) {
        console.error(err.message)
    })
    for await (const record of parser) {
        records.push(record)
    }
    return records
}

function getChainId(network) {
    // if (network === "arbitrum") {
    //  return 42161
    // }

    // if (network === "avax") {
    //  return 43114
    // }

    if (network === "telos_mainnet") {
        return 40
    }

    if (network === "telos_testnet") {
        return 41
    }

    throw new Error("Unsupported network")
}

async function getFrameSigner() {
    try {
        const frame = new ethers.providers.JsonRpcProvider("https://testnet.telos.net/evm")
        const signer = frame.getSigner()
        if (getChainId(network) !== await signer.getChainId()) {
            throw new Error("Incorrect frame network")
        }
        return signer
    } catch (e) {
        throw new Error(`getFrameSigner error: ${e.toString()}`)
    }
}

async function sendTxn(txnPromise, label) {
    const txn = await txnPromise
    console.info(`Sending ${label}...`)
    await txn.wait()
    console.info(`... Sent! ${txn.hash}`)
    await sleep(2000)
    return txn
}

async function callWithRetries(func, args, retriesCount = 3) {
    let i = 0
    while (true) {
        i++
        try {
            return await func(...args)
        } catch (ex) {
            if (i === retriesCount) {
                console.error("call failed %s times. throwing error", retriesCount)
                throw ex
            }
            console.error("call i=%s failed. retrying....", i)
            console.error(ex.message)
        }
    }
}

async function deployContract(name, args, label, options) {
    console.log(args, options)
    if (!options && typeof label === "object") {
        label = null
        options = label
    }

    let info = name
    if (label) { info = name + ":" + label }
    const contractFactory = await ethers.getContractFactory(name)
    let contract

    if (options) {
        contract = await contractFactory.deploy(...args, options)
    } else {
        contract = await contractFactory.deploy(...args)
    }
    console.log("Deploying")
    const argStr = args.map((i) => `"${i}"`).join(" ")
    console.info(`Deploying ${info} ${contract.address} ${argStr}`)
    await contract.deployTransaction.wait()
    console.info("... Completed!")
    return contract
}

async function contractAt(name, address, provider) {
    let contractFactory = await ethers.getContractFactory(name)
    if (provider) {
        contractFactory = contractFactory.connect(provider)
    }
    return await contractFactory.attach(address)
}

const tmpAddressesFilepath = path.join(__dirname, '..', '..', `.tmp-addresses-${process.env.HARDHAT_NETWORK}.json`)

function readTmpAddresses() {
    if (fs.existsSync(tmpAddressesFilepath)) {
        return JSON.parse(fs.readFileSync(tmpAddressesFilepath))
    }
    return {}
}

function writeTmpAddresses(json) {
    const tmpAddresses = Object.assign(readTmpAddresses(), json)
    fs.writeFileSync(tmpAddressesFilepath, JSON.stringify(tmpAddresses))
}

// batchLists is an array of lists
async function processBatch(batchLists, batchSize, handler) {
    let currentBatch = []
    const referenceList = batchLists[0]

    for (let i = 0; i < referenceList.length; i++) {
        const item = []

        for (let j = 0; j < batchLists.length; j++) {
            const list = batchLists[j]
            item.push(list[i])
        }

        currentBatch.push(item)

        if (currentBatch.length === batchSize) {
            console.log("handling currentBatch", i, currentBatch.length, referenceList.length)
            await handler(currentBatch)
            currentBatch = []
        }
    }

    if (currentBatch.length > 0) {
        console.log("handling final batch", currentBatch.length, referenceList.length)
        await handler(currentBatch)
    }
}

async function updateTokensPerInterval(distributor, tokensPerInterval, label) {
    const prevTokensPerInterval = await distributor.tokensPerInterval()
    if (prevTokensPerInterval.eq(0)) {
        // if the tokens per interval was zero, the distributor.lastDistributionTime may not have been updated for a while
        // so the lastDistributionTime should be manually updated here
        await sendTxn(distributor.updateLastDistributionTime({ gasLimit: 500000 }), `${label}.updateLastDistributionTime`)
    }
    await sendTxn(distributor.setTokensPerInterval(tokensPerInterval, { gasLimit: 500000 }), `${label}.setTokensPerInterval`)
}

module.exports = {
    ARBITRUM,
    AVALANCHE,
    TELOS_TESTNET,
    TELOS_MAINNET,
    providers,
    signers,
    readCsv,
    getFrameSigner,
    sendTxn,
    deployContract,
    contractAt,
    writeTmpAddresses,
    readTmpAddresses,
    callWithRetries,
    processBatch,
    updateTokensPerInterval
}