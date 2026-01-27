const { ethers } = require("ethers");
const { getFunctionData, getEventData } = require("../global_util.js");
const path = require('path');
const fs = require("fs");
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

function getEvmClient(url) {
    if (!url) throw new Error("URL not provided");
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
    const contract = new ethers.Contract(transactionData.contract_address, transactionData.abi, signer);

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

async function fetchEvmEvent(client, event_name) {
    const { event, contractAddress, abi } = await getEventData(event_name);
    const contract = new ethers.Contract(contractAddress, abi, client);

    // queryFilter(filter, fromBlock, toBlock)
    // Use -1000 to look at the last 1000 blocks
    const events = await contract.queryFilter(event, -1000, "latest");

    return events.map(event => {
        // Here you can access event.args and apply your reversal
        console.log("Tx Hash:", event.transactionHash); // Hash is found, not required as input
        return event.args; 
    });
}
module.exports = { getEvmClient, getEvmAccFromPrivKey, EvmSign, EvmSendTransaction, fetchEvmEvent, getEvmAccFromEnv, getActiveRoot};