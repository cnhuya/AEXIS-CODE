const { getFullnodeUrl, SuiClient } = require("@mysten/sui/client"); 
const { Ed25519Keypair } = require("@mysten/sui/keypairs/ed25519");
const { bcs } = require("@mysten/bcs");
const { Transaction } = require("@mysten/sui/transactions");
const { getFunctionData, getEventData, getValidatorConfig } = require("../global_util.js");

const path = require('path');
const fs = require("fs");
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const hexToUint8Array = (hex) => {
    const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
    return new Uint8Array(Buffer.from(cleanHex, 'hex'));
};

//#region Helper Functions
function Serialize(type, data, tx) {
    const normalizedType = type.toLowerCase();
    console.log("Serializing:", normalizedType, data);

// List of types supported by sui::bcs peeling functions
    const bcsTypes = ["u8", "u16", "u32", "u64", "u128", "u256"];
    
    if (bcsTypes.includes(normalizedType)) {
        // 1. Serialize using the specific BCS type (this handles Little Endian correctly)
        // No manual 32-byte padding!
        const bcsBytes = bcs[normalizedType]().serialize(data).toBytes();
        
        // 2. Wrap in a vector<u8> for your Move entry function:
        // admin_add_variable(..., data: vector<u8>)
        // We use Array.from because tx.pure.vector expects a standard array
        return tx.pure.vector('u8', Array.from(bcsBytes));
    }

    if (normalizedType === "string") {
        return tx.pure.string(data);
    }

if (normalizedType === "vector<u256>") {
    const bigIntArray = data.map(val => BigInt(val));
    
    // Explicitly serialize using the BCS definition
    const serializedData = bcs.vector(bcs.u256()).serialize(bigIntArray);
    
    // Return the serialized object
    return tx.pure(serializedData);
}
if (normalizedType === "any") {
    let bytes;
    
    if (typeof data === 'string') {
        if (/^\d+$/.test(data)) {
            // 1. It's a numeric string (like "25000000")
            // Convert to a 32-byte (u256) Little Endian array
            const bigIntValue = BigInt(data);
            bytes = bcs.u256().serialize(bigIntValue).toBytes();
        } else if (data.startsWith('0x')) {
            // 2. It's a hex string
            const cleanHex = data.slice(2);
            bytes = Uint8Array.from(Buffer.from(cleanHex, 'hex'));
        } else {
            // 3. It's actual text (like "Qiara")
            bytes = bcs.string().serialize(data).toBytes();
        }
    } else {
        bytes = data;
    }

    return tx.pure.vector('u8', Array.from(bytes));
}

    if (normalizedType === "bool") {
        // Move bool is a single byte (0 or 1)
        const bcsBytes = bcs.bool().serialize(data).toBytes();
        return tx.pure.vector('u8', Array.from(bcsBytes));
    }
    // 3. Objects (Same logic as before, these return Transaction Objects)
    if (normalizedType === "object") {
        // 1. If it's a Shared Object (has the Shared owner property)
        if (typeof data === 'object' && data.owner && data.owner.Shared) {
            return tx.sharedObjectRef({
                objectId: data.objectId,
                initialSharedVersion: data.owner.Shared.initial_shared_version,
                mutable: true,
            });
        }
        
        // 2. If it's an Owned Object (like AdminCap) or just an ID string
        const id = typeof data === 'object' ? data.objectId : data;
        return tx.object(id);
    }

    // 4. Standard Vector<u8> or Bool
    if (normalizedType === "bool") {
        return tx.pure.bool(data);
    }
    
    if (normalizedType === "vector<u8>") {
        const bytes = typeof data === 'string' ? hexToUint8Array(data) : data;
        return tx.pure.vector('u8', Array.from(bytes));
    }
    // This applies to both Input 3 (448 bytes) and Input 4 (128 bytes)
// In X:\Oracle\src\util\sui\sui_util.js

// X:\Oracle\src\util\sui\sui_util.js

// X:\Oracle\src\util\sui\sui_util.js
// X:\Oracle\src\util\sui\sui_util.js
// X:\Oracle\src\util\sui\sui_util.js
// X:\Oracle\src\util\sui\sui_util.js

if (normalizedType === "raw") {
    const rawBytes = typeof data === 'string' ? hexToUint8Array(data) : data;
    
    // Manually create the BCS vector<u8> structure
    const serializedData = bcs.vector(bcs.u8()).serialize(rawBytes);
    
    // Pass the serialized object directly
    return tx.pure(serializedData);
}
    throw new Error(`Unsupported type: ${type}`);
}

    function convertSupraTypeToSui(type) {
        switch (type) {
            case "u8":
                return "U8";
            case "u16":
                return "U16";
            case "u32":
                return "U32";
            case "u64":
                return "U64";
            case "u128":
                return "U128";
            case "u256":
                return "U256";
            case "0x1::string::String":
                return "String";
            default:
                console.log("Unknown type: " + type);
                return type;
        }
    }

//#endregion

async function getSuiClient() {
    const validator_config = await getValidatorConfig();
    const url = validator_config.SUI_RPC;  
    if (!url) throw new Error("URL not provided");
    return new SuiClient({ url });
}

async function getSuiAccFromEnv(name){
    const privKey = JSON.parse(process.env.SUI_ACCOUNTS)[name];
    console.log("Using SUI PrivKey:", privKey);
    return getSuiAccFromPrivKey(privKey);
}

async function getSuiAccFromPrivKey(privKey) {
    const signer = Ed25519Keypair.fromSecretKey(privKey);
    return signer;
}

async function SuiSign(message, signer) {
    const data = typeof message === 'string' ? new TextEncoder().encode(message) : message;
    const signatureBytes = await signer.sign(data);
    
    return Buffer.from(signatureBytes).toString('hex');
}

async function SuiBuildPayload(types, values, tx) {
    console.log(types);
    console.log(values);
    return types.map((type, index) => {
        return Serialize(type, values[index], tx);
    });
}

async function getVaultInfoByAddress(tableId, providerAddress) {
    const client = new SuiClient({ url: getFullnodeUrl('testnet') });

    try {
        // Direct lookup using the address as the Key
        const response = await client.getDynamicFieldObject({
            parentId: tableId, // The 'vaults' Table ID
            name: {
                type: 'address', 
                value: providerAddress, // e.g., "0x3787c..."
            },
        });

        if (response.error) {
            console.error(`No vault found for address: ${providerAddress}`);
            return null;
        }

        // In a Table, the 'value' field contains your struct
        const vaultInfo = response.data.content.fields.value.fields;
        console.log(vaultInfo);
        return {
            providerAddress: providerAddress,
            provider_name: vaultInfo.provider_name,
            vault_id: vaultInfo.vault_id,
            admin_cap_id: vaultInfo.admin_cap_id,
        };
    } catch (error) {
        console.error("Error fetching vault by address:", error);
        return null;
    }
}

async function getSuiObject(objectId) {
    // 1. Explicitly point to Testnet
    const client = new SuiClient({ 
        url: getFullnodeUrl('testnet') 
    });

    try {
        console.log(`Fetching object: ${objectId}...`);
        
        // 2. The modern method is getObject
        const response = await client.getObject({
            id: objectId,
            options: {
                showContent: true,
                showType: true,
                showDisplay: true,
                showOwner: true,
            },
        });

        if (response.error) {
            console.error("Sui API Error:", response.error);
            return null;
        }

        // The actual data is inside response.data
        const objectData = response.data;
        
        //console.log(objectData.content);
        //console.log("--- Object Content ---");
        return objectData;

    } catch (error) {
        // If it still says getObject is not a function, 
        // it's likely your import or SDK version is very old.
        console.error("Fetch failed. Error details:", error.message);
    }
}

// Check your ID
//const ID = '0x910471f4de985cfaa7aeeea17cb58bc2561d7bae7c2cb72b67c07bc815fbaf26';
//getSuiObject(ID);

async function SuiSendTransaction(suiClient, signer, values, type_args, transaction, aux) {
    const tx = new Transaction();
    let transactionData = await getFunctionData("sui", transaction);
    //if(transaction == "approve_withdrawal"){
    //    transactionData.package =  aux[0];
    //    transactionData.module_name = `Qiara${aux[1]}InterfaceV1`;
    //    transactionData.function_name ="grant_withdrawal_permission";
    //}
    const txPayload = await SuiBuildPayload(transactionData.args, values, tx);

    tx.moveCall({
        target: `${transactionData.package}::${transactionData.module_name}::${transactionData.function_name}`,
        // Add this line: it expects an array of strings
        typeArguments: type_args || [], 
        arguments: txPayload,
    }); 

    tx.setGasBudget(10000000); 

    const result = await suiClient.signAndExecuteTransaction({
        signer: signer,
        transaction: tx,
        options: { showEffects: true },
    });

    console.log(result);
    return result;
}

async function c_SuiSendTransaction(suiClient, signer, values, args, transactionData) {
    const tx = new Transaction();

    const txPayload = await SuiBuildPayload(args, values, tx);

    tx.moveCall({
        target: `${transactionData.package}::${transactionData.module_name}::${transactionData.function_name}`,
        arguments: txPayload,
    }); 

    // MANUALLY SET BUDGET to bypass the auto-estimation mismatch
    tx.setGasBudget(10000000); // 0.1 SUI

    const result = await suiClient.signAndExecuteTransaction({
        signer: signer,
        transaction: tx,
        options: { showEffects: true },
    });

    console.log(result);

    return result;
}

async function fetchSuiEvent(event_name) {
    let client = await getSuiClient();
    let event = await getEventData("sui", event_name);
    
    const events = await client.queryEvents({
        query: {
            MoveEventType: `${event.event}`,
        },
    });

    return events.data.map(eventEnvelope => {
        return {
            // Spread the original event data (user, amount, token_type, etc.)
            ...eventEnvelope.parsedJson,
            // Add the metadata
            hash: eventEnvelope.id.txDigest,
            timestamp: eventEnvelope.timestampMs,
            chain: 'sui'
        };
    });
}

//getSuiObject("0x0734d707ed0babd6b36c9d6c6fc0d79983f055d8a2a202eb0f2d201a6731f675");
//getVaultInfoByAddress("0x1ff881ed73156a6b529a3f7d729e488576db4a5c062337fe62b47bc5e448f9e1", "0xf3fdecf7cfd3d6a748d7e5ad551a35b1720a4e9a280883299e93a12d38c1e791");
module.exports = { getSuiClient, getSuiAccFromPrivKey, SuiSign, SuiSendTransaction, getVaultInfoByAddress, fetchSuiEvent, getSuiAccFromEnv, getSuiObject, c_SuiSendTransaction, convertSupraTypeToSui };