const { getEvmAccFromPrivKey, EvmSign, getEvmClient, getEvmAddress, EvmSendTransaction,getEvmAccFromEnv, getActiveRoot } = require("./evm_util");
const { fieldToValue, fieldToStr, loadGeneratedProof } = require("../global_util");
const fs = require('fs');
const path = require('path');

const formatForRemix = (batchData) => {
    const { pA, pB, pC, publicSignals } = batchData;

    const normalize = (val) => {
        const str = typeof val === 'string' ? val : val.toString();
        const hex = str.startsWith('0x') ? str.slice(2) : BigInt(str).toString(16);
        return "0x" + hex.padStart(64, '0').toLowerCase();
    };

    return [
        pA.map(normalize),
        [
            [normalize(pB[0]), normalize(pB[1])],
            [normalize(pB[2]), normalize(pB[3])]
        ],
        pC.map(normalize),
        publicSignals.map(normalize)
    ];
};

const assembleAddress = (highSignal, lowSignal) => {
    const high = BigInt(highSignal);
    const low = BigInt(lowSignal);

    // 32 hex chars in the low signal * 4 bits per char = 128 bits
    const combined = (high << 128n) | low;

    // Convert to hex and ensure it is exactly 40 chars (20 bytes)
    // .slice(-40) removes any accidental leading zeros from over-shifting
    let hex = combined.toString(16).padStart(40, '0').slice(-40);
    
    return "0x" + hex.toLowerCase();
};


//0x0092aafae36fd7d7abeda9297f05724ecba21193
//0x92AafAC1636Fd7d7abEDA9297f05724eCBA21193
//0x0092aafae36fd7d7abeda9297f05724ecba21193
//0x92aafac1636fd7d7abeda9297f05724ecba21193
const result = assembleAddress("2460678849", "132174294339333013904321148690198827411");
console.log(result);
async function evm_run(chain, type, fun) {
    try {
        const rawBatchData = loadGeneratedProof(type); 
        console.log(rawBatchData);
        let user = assembleAddress(rawBatchData.publicSignals[2], rawBatchData.publicSignals[1]);
        let token = assembleAddress(rawBatchData.publicSignals[4], rawBatchData.publicSignals[3]);
        let vault = assembleAddress(rawBatchData.publicSignals[6], rawBatchData.publicSignals[5]);
        console.log("user:", user, "token:", token, "vault:", vault);
        const formattedArgs = formatForRemix(rawBatchData);
        await EvmSendTransaction(await getEvmAccFromEnv(await getEvmClient(chain), 'acc1'),chain, formattedArgs, fun);
    } catch (error) {
        console.error("[EVM] Execution failed:", error);
    }
}
//evm_run("base", "balances", "approve_withdrawal");
module.exports = { evm_run };