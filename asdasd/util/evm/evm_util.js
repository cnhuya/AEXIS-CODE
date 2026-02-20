const { ethers } = require("ethers");
const { getFunctionData, getEventData, getValidatorConfig } = require("../global_util.js");
const path = require('path');
const fs = require("fs");
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

function evmEncode(type, rawValue) {
    const abiCoder = new ethers.AbiCoder();
    return abiCoder.encode([type], [rawValue]);
}

function convertSupraTypeToEvm(type) {
    switch (type) {
        case "u8":
            return "uint8";
        case "u16":
            return "uint16";
        case "u32":
            return "uint32";
        case "u64":
            return "uint64";
        case "u128":
            return "uint128";
        case "u256":
            return "uint256";
        case "0x1::string::String":
            return "string";
        default:
            console.log("Unknown type: " + type);
            return type;
    }
}


async function getEvmClient(chain) {
    const validator_config = await getValidatorConfig();
    const rpcKey = `${chain.toUpperCase()}_RPC`;
    const url = validator_config[rpcKey]; 
    if (!url) {
        throw new Error(`RPC URL for ${chain} (key: ${rpcKey}) not found in config`);
    }
    return new ethers.JsonRpcProvider(url);
}

async function getEvmAccFromEnv(client, name){
    const privKey = JSON.parse(process.env.EVM_ACCOUNTS)[name];
    return getEvmAccFromPrivKey(client, privKey);
}

async function getEvmAccFromPrivKey(client, privKey) {
    const formattedKey = privKey.startsWith('0x') ? privKey : `0x${privKey}`;

    const signer = new ethers.Wallet(formattedKey, client);
    return signer;
}

async function EvmSign(message, signer) {
    return await signer.signMessage(message);
}

async function getActiveRoot(client) {
    // 1. Setup Connection (Replace with your RPC URL)
    // 2. Contract Details
    const contractAddress = "0x04104ec17cb5f6484F0ec21C5DdbC79e0E781ba8";
    
    // Minimal ABI to access the variable
    const abi = [
        "function activeRoot() public view returns (uint256)"
    ];

    // 3. Create Contract Instance
    const contract = new ethers.Contract(contractAddress, abi, client);

    try {
        // 4. Call the variable (it acts like a function)
        const root = await contract.activeRoot();
        
        return root.toString();
    } catch (error) {
        console.error("Error fetching activeRoot:", error);
    }
}

async function EvmSendTransaction(signer, chain, values, actionName) {
    // 1. Build the transaction data
    // ["0xAddress", "ContractAbi", "FunctionName"]
    const transactionData = await getFunctionData(chain, actionName);
    console.log("Transaction Data:", transactionData);  
    const contract = new ethers.Contract(transactionData.contract_address[0], transactionData.abi, signer);

    // 5. Execute
    try {
        const tx = await contract[transactionData.functionName](...values);
        console.log(`⏳ Transaction Sent! [${chain} - ${actionName}]`);
        
        const receipt = await tx.wait();
        console.log("🚀 Transaction Confirmed! Hash:", receipt.hash);
        
        return receipt.hash;
    } catch (error) {
        console.error("❌ Transaction Failed:", error);
        throw error;
    }
}


async function fetchEvmEvent(chain, event_name) {
    // 1. Get the data. Based on your console.log, this IS the event config.
    const eventConfig = await getEventData(chain, event_name);
    
    // DEBUG: Look at your console.log. It shows eventConfig has 'contractAddresses' (plural)
    // and 'abi'. So we use those exact names.

    if (!eventConfig || !eventConfig.contractAddresses) {
        console.error(`Could not find config for ${chain} ${event_name}`);
        return { [chain]: {} };
    }

    // 2. Use eventConfig.contractAddresses
    const results = await Promise.all(eventConfig.contractAddresses.map(async (address) => {
        const provider = await getEvmClient(chain);
        
        // Use eventConfig.abi
        const contract = new ethers.Contract(address, eventConfig.abi, provider);

        // Use eventConfig.event (which is 'Deposit')
        const logs = await contract.queryFilter(eventConfig.event, -1000, "latest");

        const transactions = logs.map(log => ({
            hash: log.transactionHash,
            timestamp: Math.floor(Date.now() / 10000),
            block: log.blockNumber,
            user: log.args.user,
            token: log.args.token,
            amount: log.args.amount.toString()
        }));

        return { address, transactions };
    }));

    // 3. Group data
    const addressGroupedData = results.reduce((acc, current) => {
        acc[current.address] = current.transactions;
        return acc;
    }, {});

    return {
        [chain]: addressGroupedData
    };
}

module.exports = { getEvmClient, getEvmAccFromPrivKey, EvmSign, EvmSendTransaction, fetchEvmEvent, getEvmAccFromEnv, getActiveRoot, evmEncode, convertSupraTypeToEvm};