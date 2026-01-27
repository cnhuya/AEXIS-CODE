const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { getFunctionData, getEventData } = require("../global_util.js");

//#region Helper Functions
    function serializeU8Vector(nums) {
    const lengthBytes = encodeULEB128(nums.length);
    const valueBytes = nums.flatMap(num => Array.from(BCS.bcsSerializeU8(num)));
    return Uint8Array.from([...lengthBytes, ...valueBytes]);
    }

    function encodeULEB128(value) {
    const bytes = [];
    do {
        let byte = value & 0x7f;
        value >>>= 7;
        if (value !== 0) {
        byte |= 0x80;
        }
        bytes.push(byte);
    } while (value !== 0);
    return bytes;
    }

    function Serialize(type, data){
        console.log(type, data);
        if (type == "string") {
            return serializeU8Vector(Array.from(Buffer.from(data.toString())));
        } else if (type == "vector<u8>") {
            return BCS.bcsSerializeBytes(data);
        } else if (type == "vector<vector<u8>>") {
            // 1. Encode the number of inner vectors (outer length)
            const lengthBytes = encodeULEB128(data.length);
            
            // 2. Serialize each inner vector<u8>
            // BCS.bcsSerializeBytes already adds the ULEB128 length for each inner array
            const serializedInnerVectors = data.flatMap(innerVec => 
                Array.from(BCS.bcsSerializeBytes(innerVec))
            );
            
            return Uint8Array.from([...lengthBytes, ...serializedInnerVectors]);
        } else if (type == "u8") {
            return BCS.bcsSerializeU8(data);
        } else if (type == "u16") {
            return BCS.bcsSerializeU16(data);
        } else if (type == "u32") {
            return BCS.bcsSerializeU32(data);
        } else if (type == "u64") {
            return BCS.bcsSerializeUint64(data);
        } else if (type == "u128") {
            return BCS.bcsSerializeU128(data);
        } else if (type == "u256") {
            return BCS.bcsSerializeU256(data);
        }else if (type == "bool") {
            return BCS.bcsSerializeBool(data);
        } else if (type == "address") {
            let hex;
            
            // Check if the data is a long decimal string or BigInt
            if (typeof data === 'string' && !data.startsWith('0x') && data.length > 40) {
                // Convert decimal string to hex and pad to 64 chars (32 bytes)
                hex = BigInt(data).toString(16).padStart(64, '0');
            } else {
                // It's already hex or a HexString object
                hex = (data.hexString || data).toString();
                if (hex.startsWith('0x')) hex = hex.slice(2);
                // Ensure even length for the SDK
                if (hex.length % 2 !== 0) hex = '0' + hex;
            }

            const finalHex = hex.startsWith('0x') ? hex : '0x' + hex;
            let x = HexString.ensure(finalHex).toUint8Array();
            
            console.log("Encoded Address:", finalHex);
          //  console.log(x);
            return x;
        } else {
            console.log("Unsupported type:", type);
        }
    }
//#endregion


async function getSupraClient(url) {
    if (!url) throw new Error("URL not provided");
    return await SupraClient.init(url);
}

async function getSupraAccFromPrivKey(privKey) {
    const signer = new SupraAccount(Buffer.from(privKey.replace("0x", ""), "hex"));
    return signer;
}

async function getSupraAddress(signer){
    return signer.address();
}

async function SupraSign(message, signer) {
    const sig = signer.signBuffer(message);
    return sig;
}

async function SupraBuildPayload(types, values) {
    const payload = types.map((type, index) => {
        const value = values[index];
        return Serialize(type, value);
    });

    return payload;
}

async function SupraSendTransaction(supraClient, signer, values, transaction){
    // 1. Build the transaction data
    // ["0xAddress", "ModuleName", "FunctionName"]
    const transactionData = await getFunctionData("supra", transaction);
    // 3. Build the payload with your specific serialization rules
    const txPayload = await SupraBuildPayload(transactionData.args, values);

    // 4. Construct and send the transaction
    const senderAddr = signer.address();
    //console.log(supraClient);
    const accountInfo = await supraClient.getAccountInfo(senderAddr);

    //console.log(transactionData);

    const rawTx = await supraClient.createSerializedRawTxObject(
        senderAddr,
        accountInfo.sequence_number,
        transactionData.module_address,
        transactionData.module_name,
        transactionData.function_name,
        [],
        txPayload
    );
        
    const txResponse = await supraClient.sendTxUsingSerializedRawTransaction(
        signer, 
        rawTx, 
        { 
            enableWaitForTransaction: true,
            enableTransactionSimulation: false // Optional: set to true if you want to pre-check for failures
        }
    );

    console.log("🚀 Transaction Successful! Hash:", txResponse);
    return txResponse;
}

async function test_SupraSendTransaction(supraClient, signer, values, transaction, sequence_number){
    // 1. Build the transaction data
    // ["0xAddress", "ModuleName", "FunctionName"]
    const transactionData = await getFunctionData("supra", transaction);
    // 3. Build the payload with your specific serialization rules
    const txPayload = await SupraBuildPayload(transactionData.args, values);

    // 4. Construct and send the transaction
    const senderAddr = signer.address();
    //console.log(supraClient);

    //console.log(transactionData);

    const rawTx = await supraClient.createSerializedRawTxObject(
        senderAddr,
        sequence_number,
        transactionData.module_address,
        transactionData.module_name,
        transactionData.function_name,
        [],
        txPayload
    );
        
    const txResponse = await supraClient.sendTxUsingSerializedRawTransaction(
        signer, 
        rawTx, 
        { 
            enableWaitForTransaction: false,
            enableTransactionSimulation: false // Optional: set to true if you want to pre-check for failures
        }
    );

    console.log("🚀 Transaction Successful! Hash:", txResponse);
    return txResponse;
}

async function fetchSupraEvent(event_name) {
    console.log("Fetching Supra Event:", event_name);
    let event = await getEventData("supra", event_name);
    
    const response = await fetch(`https://rpc-testnet.supra.com/rpc/v3/events/${event.event}`, {
        method: 'GET',
        headers: { "Accept": "*/*" },
    });
    
    let result = await response.json();

    // Map the raw RPC result to your desired format
    return result.data.map(item => ({
        hash: item.transaction_hash,
        block: item.block_height,
        data: item.event.data
    }));
}

module.exports = { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, getSupraAddress, fetchSupraEvent, test_SupraSendTransaction };