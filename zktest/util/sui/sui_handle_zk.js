const fs = require('fs');
const { getSuiAccFromEnv, SuiSendTransaction, getSuiClient, getSuiObject } = require("./sui_util.js");
const path = require('path');
// In nodejs target, wasm-pack generates a direct require-able module
const { convert_public_inputs, convert_proof_and_vkey } = require("./pkg/format_converter.js");


function extractRootToDecimal(hexString) {
    const bytes = Buffer.from(hexString, 'hex');
    const rootBytes = bytes.slice(32, 64);

    let result = BigInt(0);
    for (let i = 0; i < rootBytes.length; i++) {
        result += BigInt(rootBytes[i]) << (8n * BigInt(i));
    }

    return result.toString();
}
;
function convertLittleEndianBytesToDecimal(bytes) {
    let result = BigInt(0);

    for (let i = 0; i < bytes.length; i++) {
        result += BigInt(bytes[i]) << (8n * BigInt(i));
    }

    return result.toString();
}

async function sui_run(type, fun) {
    console.log('[SUI] --- Starting Sui ArkWorks Proof Generation ---');

    const BasePath = path.join(__dirname, `../../zk/${type}/`);
    // 1. Load the JSON files
    const vkey_json_str = fs.readFileSync(BasePath + "verification_key.json", "utf8");
    const public_json_str = fs.readFileSync(BasePath + "public.json", "utf8");
    const proof_json_str = fs.readFileSync(BasePath + "proof.json", "utf8");
    try {
        // 2. Convert Public Inputs
        const public_res_raw = convert_public_inputs(public_json_str);
        const public_res = JSON.parse(public_res_raw);
        // 3. Convert Proof and VKey
        const pv_res_raw = convert_proof_and_vkey(proof_json_str, vkey_json_str);
        const pv_res = JSON.parse(pv_res_raw);

        // --- MATCHING SUI EXAMPLE LOGGING FORMAT ---
        
        //console.log(`Verifying key: ${pv_res.vkey_hex}`);
        //console.log(`Proof: ${pv_res.proof_hex}`);
        //console.log(`Public inputs: ${public_res.arkworks_format}`);

        // Optional metadata
        //console.log(`\n(Metadata: VK Length ${pv_res.vkey_hex.length / 2} bytes, Public Inputs: ${public_res.count})`);

        console.log("[SUI] --- ArkWorks Conversion Complete ---");

        let offchain_root = extractRootToDecimal(public_res.arkworks_format);
        
        let obj = await getSuiObject('0x910471f4de985cfaa7aeeea17cb58bc2561d7bae7c2cb72b67c07bc815fbaf26');
        let onchain_root = convertLittleEndianBytesToDecimal(obj.content.fields.root);

        console.log(`[SUI] Extracted Validator Root from Public Inputs: ${offchain_root}`);
        console.log(`[SUI] On-Chain Validator Root: ${onchain_root}`);
        if(onchain_root !== offchain_root){
            let values = [
                obj,                 // arg 0: &mut Storage
                public_res.arkworks_format,   // arg 1: public_inputs (vector<u8>)
                pv_res.proof_hex              // arg 2: proof_points (vector<u8>)
            ];

            await sendProof(values, fun);
        }
        console.log("[SUI] ✅ onchain root matches offchain root, no update needed.");
    } catch (err) {
        console.error("Conversion Error:", err);
    }
}

async function sendProof(values, fun) {
    let suiClient = await getSuiClient("https://fullnode.testnet.sui.io:443");
    
    let signer = await getSuiAccFromEnv("acc1");
    let result = SuiSendTransaction(suiClient, signer, values, fun);
    return result;
}

//sui_run().catch(console.error);

module.exports = { sui_run };