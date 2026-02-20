const fs = require('fs');
const { getSuiAccFromEnv, SuiSendTransaction, getSuiClient, getSuiObject, getVaultInfoByAddress } = require("./sui_util.js");
const path = require('path');
// In nodejs target, wasm-pack generates a direct require-able module
const { convert_public_inputs, convert_proof_and_vkey } = require("./pkg/format_converter.js");
const { fieldToValue, loadGeneratedProof, convertVaultStrToAddress, convertTokenStrToAddress, getFields,split256BitValue, convertChainStrToID}  = require("../global_util.js");
const { get_consensus_vote_data }  = require("../fetchers.js");
const { buildPoseidon, buildEddsa } = require("circomlibjs");
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

const reassembleString = (highSignal, lowSignal) => {
    const high = BigInt(highSignal);
    const low = BigInt(lowSignal);

    // 1. Convert to hex and pad to 32 chars (16 bytes) each
    const highHex = high.toString(16).padStart(32, '0');
    const lowHex = low.toString(16).padStart(32, '0');

    const combinedHex = highHex + lowHex;

    // 2. Convert hex to String
    let result = "";
    for (let i = 0; i < combinedHex.length; i += 2) {
        const charCode = parseInt(combinedHex.substr(i, 2), 16);
        if (charCode === 0) continue; 
        result += String.fromCharCode(charCode);
    }

    let finalStr = result.trim();

    // 3. CRITICAL FIX: Ensure the Sui Address format is restored
    // If the string looks like a type but is missing '0x', add it.
    if (!finalStr.startsWith('0x') && /^[0-9a-fA-F]{10,}/.test(finalStr)) {
        finalStr = '0x' + finalStr;
    }

    return finalStr;
};

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
        let type_args = [];
        console.log(`Verifying key: ${pv_res.vkey_hex}`);
        console.log(`Proof: ${pv_res.proof_hex}`);
        console.log(`Public inputs: ${public_res.arkworks_format}`);

        // Optional metadata
        //console.log(`\n(Metadata: VK Length ${pv_res.vkey_hex.length / 2} bytes, Public Inputs: ${public_res.count})`);

        console.log("[SUI] --- ArkWorks Conversion Complete ---");
        let values = [];
        let aux = [];
        let offchain_root;
        let obj_storage;
        let onchain_root;
        const publicArray = JSON.parse(public_json_str);

        if(fun == "sendZKP"){
            offchain_root = extractRootToDecimal(public_res.arkworks_format);
            obj_storage = await getSuiObject('0x910471f4de985cfaa7aeeea17cb58bc2561d7bae7c2cb72b67c07bc815fbaf26');
            onchain_root = convertLittleEndianBytesToDecimal(obj_storage.content.fields.root);

            values = [
                obj_storage,                 // arg 0: &mut Storage
                public_res.arkworks_format,   // arg 1: public_inputs (vector<u8>)
                pv_res.proof_hex              // arg 2: proof_points (vector<u8>)
            ];
        } else if (fun == "load_variables_sui"){
            offchain_root = extractRootToDecimal(public_res.arkworks_format);
            obj_state = await getSuiObject('0xca527467d649cd5111a845bd76364de43d2a773038d1df901d19746d7601efaf');
            obj_registry = await getSuiObject('0xfe8333a2362d770b2e4051a5d1c272e07477385018de38fea44310015f32e1bc');
            onchain_root = convertLittleEndianBytesToDecimal(obj_state.content.fields.root);

            values = [
                obj_registry,
                fieldToStr(publicArray[0]),
                fieldToStr(publicArray[1]),
                publicArray[2],
                obj_state,
                public_res.arkworks_format,   // arg 1: public_inputs (vector<u8>)
                pv_res.proof_hex              // arg 2: proof_points (vector<u8>)
            ];

        } else if (fun == "approve_withdrawal"){
            onchain_root = "a";
            const rawBatchData = loadGeneratedProof(type); 

            
        // --- Corrected Extraction & Mapping ---
        let ab = await get_consensus_vote_data(rawBatchData.publicSignals[1]);

            //let provider = await convertVaultStrToAddress((extracted.provider), "Sui");
           // console.log(extracted);
           // let provider_info = await getVaultInfoByAddress("0x1ff881ed73156a6b529a3f7d729e488576db4a5c062337fe62b47bc5e448f9e1", await convertVaultStrToAddress((extracted.provider), "Sui"));
           // console.log(provider_info);
            //obj_vault = await getSuiObject(provider_info.vault_id);
            obj_manager = await getSuiObject("0xfa2310eafa9bdd1adcc49162251b6742d91cd78544dfdd6878aad38ce54a963b");
            obj_nullifiers = await getSuiObject("0x9cf5d794f9214c71c160b5f614b9751b7283f65e87400d4e1abf86ff626e8bec");
           // aux = [provider, provider_info.provider_name]; // package addr + name of the provider package (neccesary to built function)
            //console.log(aux);
           // console.log((extracted.symbol));
            type_args.push("0x41253bc6248549a378e5caa3a4dc3131ca11a70fdcfdd1a46a2dba229bbb1ac5::USDC::USDC");

            values = [
                obj_manager,
                obj_nullifiers,
                public_res.arkworks_format,   // arg 1: public_inputs (vector<u8>)
                pv_res.proof_hex              // arg 2: proof_points (vector<u8>)
            ];

        }
        console.log(`[SUI] Extracted Validator Root from Public Inputs: ${offchain_root}`);
        console.log(`[SUI] On-Chain Validator Root: ${onchain_root}`);

        if(onchain_root !== offchain_root){
            await sendProof(values, type_args, fun, aux);
            console.log("[SUI] ℹ️  onchain root does NOT match offchain root, sending update TX.");
        } else {
            console.log("[SUI] ✅  onchain root matches offchain root, no update needed.");
            return 
        }
    } catch (err) {
        console.error("Conversion Error:", err);
    }
}


async function sendProof(values, type_args, fun, aux) {
    let suiClient = await getSuiClient("https://fullnode.testnet.sui.io:443");

    let signer = await getSuiAccFromEnv("acc1");
    let result = SuiSendTransaction(suiClient, signer, values, type_args, fun, aux);
    return result;
}

sui_run("balances", "approve_withdrawal").catch(console.error);
//reassembleString(64427078003718060515748316809983767609n.toString(), 77679142552019635899334916732685112226059767805428047634755611535914136550126690896155595695158722803674615230222340429456474052568341276585702409283n.toString())
module.exports = { sui_run };