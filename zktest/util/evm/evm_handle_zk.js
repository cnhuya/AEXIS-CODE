const { getEvmAccFromPrivKey, EvmSign, getEvmClient, getEvmAddress, EvmSendTransaction,getEvmAccFromEnv, getActiveRoot } = require("./evm_util");
const { prepareBatch } = require("../prover.js");

const formatForRemix = (batchData) => {
    const { pA, pB, pC, publicSignals } = batchData;

    const normalize = (val) => {
        // Handle potential non-string inputs from BigInt/Numbers
        const str = typeof val === 'string' ? val : val.toString();
        const clean = str.startsWith('0x') ? str.slice(2) : str;
        // If it's a decimal string, BigInt(str).toString(16) would be safer, 
        // but padStart works if prepareBatch already sent hex-compatible strings.
        const hex = str.startsWith('0x') ? clean : BigInt(str).toString(16);
        return "0x" + hex.padStart(64, '0').toLowerCase();
    };

    return [
        pA.map(normalize),
        // Manually group the flat pB array into [[pB[0], pB[1]], [pB[2], pB[3]]]
        [
            [normalize(pB[0]), normalize(pB[1])],
            [normalize(pB[2]), normalize(pB[3])]
        ],
        pC.map(normalize),
        publicSignals.map(normalize)
    ];
};

async function sendProof(chain, args, fun){
    let signer = await getEvmAccFromEnv(getEvmClient('https://base-sepolia-public.nodies.app'), 'acc1');
    console.log(signer);
    console.log(args);
    await EvmSendTransaction(signer, chain, args, fun);
}

async function evm_run(type, fun) {
    try {

        let onchain_root = await getActiveRoot(getEvmClient('https://base-sepolia-public.nodies.app'));

        // 1. Await the async proof generation
        const rawBatchData = await prepareBatch(type); 
        
        let offchain_root = rawBatchData.publicSignals[1];

        //console.log("[EVM] Raw Batch Data:", rawBatchData);
        console.log("[EVM] On-chain Root:", onchain_root);
        console.log("[EVM] Off-chain Root:", offchain_root);
        if (onchain_root !== offchain_root) {
            // 2. Format the resolved array
            const formattedArgs = formatForRemix(rawBatchData);
            
            // 3. Send the transaction
            await sendProof("base", formattedArgs, fun);
        } else {
            console.log("[EVM] ✅ Roots match; no transaction sent.");
        }
        
    } catch (error) {
        console.error("[EVM] Execution failed:", error);
    }
}

//evm_run();
module.exports = { evm_run };