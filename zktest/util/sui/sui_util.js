const { getFullnodeUrl, SuiClient } = require("@mysten/sui/client"); 
const { Ed25519Keypair } = require("@mysten/sui/keypairs/ed25519");
const { bcs } = require("@mysten/bcs");
const { Transaction } = require("@mysten/sui/transactions");
const { getFunctionData, getEventData } = require("../global_util.js");

const path = require('path');
const fs = require("fs");
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

//#region Helper Functions
    function Serialize(type, data, tx){

        const hexToUint8Array = (hex) => {
                const matches = hex.match(/.{1,2}/g);
                if (!matches) return new Uint8Array();
                return new Uint8Array(matches.map((byte) => parseInt(byte, 16)));
            };
            console.log(type, data );
        if (type == "string") {
            return tx.pure.string(data);
        } else if (type == "U8") {
            return bcs.u8().serialize(data).toBytes();
        } else if (type == "U16") {
            return bcs.u16().serialize(data).toBytes();
        } else if (type == "U32") {
            return bcs.u32().serialize(data).toBytes();
        } else if (type == "U64") {
            return bcs.u64().serialize(data).toBytes();
        } else if (type == "U128") {
            return bcs.u128().serialize(data).toBytes();
        } else if (type == "U256") {
            return bcs.u256().serialize(data).toBytes();
        }else if (type == "bool") {
            return bcs.bool().serialize(data).toBytes();
        } else if (type == "array_vector<u8>") {
            const flattened = [].concat(...data);
            return tx.pure.vector('u8', flattened);
        } else if (type == "vector<u8>") {
            const bytes = typeof data === 'string' ? hexToUint8Array(data) : data;
            return tx.pure.vector('u8', Array.from(bytes));
        } if (type === "object") {
    // If we have the full object data, construct the shared object reference manually
    if (typeof data === 'object' && data.owner && data.owner.Shared) {
        return tx.sharedObjectRef({
            objectId: data.objectId,
            initialSharedVersion: data.owner.Shared.initial_shared_version,
            mutable: true, // Set to true because your function uses &mut Storage
        });
    }
    // Fallback to just the ID if it's not a shared object
    return tx.object(typeof data === 'object' ? data.objectId : data);
}
    return tx.pure(data);
    }
//#endregion

function getSuiClient(url) {
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
    return types.map((type, index) => {
        return Serialize(type, values[index], tx);
    });
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
        
        //console.log("--- Object Content ---");
        return objectData;

    } catch (error) {
        // If it still says getObject is not a function, 
        // it's likely your import or SDK version is very old.
        console.error("Fetch failed. Error details:", error.message);
    }
}

// Check your ID
const ID = '0x910471f4de985cfaa7aeeea17cb58bc2561d7bae7c2cb72b67c07bc815fbaf26';
getSuiObject(ID);

async function SuiSendTransaction(suiClient, signer, values, transaction) {
    const tx = new Transaction();
    const transactionData = await getFunctionData("sui", transaction);

    const txPayload = await SuiBuildPayload(transactionData.args, values, tx);

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
async function fetchSuiEvent(client, event_name) {
    let event = await getEventData("supra", event_name);
    const events = await client.queryEvents({
        query: {
            MoveEventType: `${event}`,
        },
    });

    return events.data.map(event => {
        return event.parsedJson;
    });
}
module.exports = { getSuiClient, getSuiAccFromPrivKey, SuiSign, SuiSendTransaction, fetchSuiEvent, getSuiAccFromEnv, getSuiObject };