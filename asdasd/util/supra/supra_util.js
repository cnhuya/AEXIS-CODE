const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { getFunctionData, getEventData, getValidatorConfig } = require("../global_util.js");

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

    function Serialize(type, data, additionalArgTypes){
        console.log(type, data);
        if (type == "string") {
            return serializeU8Vector(Array.from(Buffer.from(data.toString())));
        } else if (type === "vector<string>") {
        // 1. Encode the number of strings in the vector (ULEB128)
        const outerLengthBytes = encodeULEB128(data.length);
        
        // 2. Serialize each string as a vector<u8>
        const serializedStrings = data.map(str => {
            // Convert the string to a Uint8Array (UTF-8)
            const bytes = Uint8Array.from(Buffer.from(str.toString(), 'utf8'));
            
            // Use bcsSerializeBytes to get the ULEB128 length + content
            return Array.from(BCS.bcsSerializeBytes(bytes));
        }).flat();

        // 3. Combine outer length + all serialized strings
            return Uint8Array.from([...outerLengthBytes, ...serializedStrings]);
        } else  if (type == "vector<u8>") {
    // If the data is a hex string (address), we must treat it as 32 raw bytes
    if (typeof data === 'string' && data.startsWith('0x')) {
        const hex = data.slice(2).padStart(64, '0');
        const rawBytes = Uint8Array.from(Buffer.from(hex, 'hex'));
        
        // This adds the 0x20 (32) length prefix Move needs for vector<u8>
        return BCS.bcsSerializeBytes(rawBytes);
    }
    
    // Fallback for standard byte arrays
    return BCS.bcsSerializeBytes(data);
 } else if (type === "vector<vector<u8>>") {
    // 1. Outer length (number of elements in the main list)
    const outerLengthBytes = encodeULEB128(data.length);
    
    const serializedInnerVectors = data.map((innerVal, index) => {
        const innerType = additionalArgTypes && additionalArgTypes[index] 
            ? additionalArgTypes[index] 
            : "string";

        let rawContent;

        if (innerType === "u64") {
            // Numbers are 8 bytes raw
                rawContent = BCS.bcsSerializeUint64(BigInt(innerVal));
        } else if (innerType === "vector<u8>") {
            // 1. Convert hex string to raw bytes (Uint8Array)
            let rawBytes;
            if (typeof innerVal === 'string') {
                const hex = innerVal.startsWith('0x') ? innerVal.slice(2) : innerVal;
                rawBytes = Uint8Array.from(Buffer.from(hex, 'hex'));
            } else {
                rawBytes = Uint8Array.from(innerVal);
            }

            // 2. Wrap it with its length prefix (ULEB128)
            // This turns [0x92, 0xf3...] into [0x20, 0x92, 0xf3...] (0x20 is 32 bytes)
            rawContent = BCS.bcsSerializeBytes(rawBytes);
        } else if (innerType === "u128") {
            rawContent = BCS.bcsSerializeU128(BigInt(innerVal));
        } else if (innerType === "u256") {
            rawContent = BCS.bcsSerializeU256(BigInt(innerVal));
        } else if (innerType === "bool") {
            rawContent = BCS.bcsSerializeBool(innerVal === true || innerVal === "true");
        } else if (innerType === "address") {
            let hex = innerVal.startsWith('0x') ? innerVal.slice(2) : innerVal;
            rawContent = Uint8Array.from(Buffer.from(hex.padStart(64, '0'), 'hex'));
        }else if (innerType === "pure") {
    // --- THE FIX FOR SIGNATURES/BYTES ---
    // If it's already a Buffer or Uint8Array, use it. 
    // If it's a hex string, convert it to raw bytes.
    if (typeof innerVal === 'string') {
        const hex = innerVal.startsWith('0x') ? innerVal.slice(2) : innerVal;
        rawContent = Uint8Array.from(Buffer.from(hex, 'hex'));
    } else {
        rawContent = Uint8Array.from(innerVal);
    }
    // Note: Do NOT use bcsSerializeBytes here if the contract expects a fixed size,
    // but usually, Move vector<u8> expects the length prefix provided by the return below.
} else {
            // --- THE STRING FIX ---
            // For strings, we must add the "data length" prefix first
            const bytes = typeof innerVal === 'string'
                ? Uint8Array.from(Buffer.from(innerVal, 'utf8'))
                : Uint8Array.from(innerVal);
            
            // This turns "USDC" into [0x04, 0x55, 0x53, 0x44, 0x43]
            rawContent = BCS.bcsSerializeBytes(bytes); 
        }

        // --- THE CONTAINER WRAPPING ---
        // This adds the "container length" prefix.
        // For USDC, this turns it into [0x05, 0x04, 0x55, 0x53, 0x44, 0x43]
        // For u64 (1111), this turns it into [0x08, 0x57, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        return Array.from(BCS.bcsSerializeBytes(rawContent));
    }).flat();

        return Uint8Array.from([...outerLengthBytes, ...serializedInnerVectors]);
        } else if (type === "vector<u256>") {
            // 1. Encode the number of elements (ULEB128)
            const lengthBytes = encodeULEB128(data.length);
            
            // 2. Serialize each u256 element
            const serializedElements = data.map(val => {
                // Ensure we are working with BigInt for large numbers
                const bigIntVal = BigInt(val);
                // BCS Uint256 is exactly 32 bytes
                return Array.from(BCS.bcsSerializeU256(bigIntVal));
            }).flat();

            // 3. Combine length prefix with the flattened u256 bytes
            return Uint8Array.from([...lengthBytes, ...serializedElements]);
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


async function getSupraClient() {
    const validator_config = await getValidatorConfig();
    const url = validator_config.SUPRA_RPC;  
    if (!url) throw new Error("URL not provided");
    console.log(url);
    return await SupraClient.init(url);
}

async function getSupraAccFromPrivKey(privKey) {
    const signer = new SupraAccount(Buffer.from(privKey.replace("0x", ""), "hex"));
    return signer;
}

async function getSupraAddress(signer){
    return signer.address();
}

async function SupraSign(signer, data, types) {
    // 1. Serialize each element using your existing Serialize function
    const serializedParts = data.map((item, index) => {
        const type = types[index];
        // Ensure we call your Serialize function
        return Serialize(type, item);
    });

    // 2. Flatten the array of Uint8Arrays into one single Uint8Array
    // We calculate total length first for efficiency
    const totalLength = serializedParts.reduce((sum, part) => sum + part.length, 0);
    const combinedBuffer = new Uint8Array(totalLength);
    
    let offset = 0;
    for (const part of serializedParts) {
        combinedBuffer.set(part, offset);
        offset += part.length;
    }

    // 3. Sign the combined buffer
    const sig = signer.signBuffer(combinedBuffer);

    // Return the signature and the hex version of the message for debugging
    return { 
        signature: sig, 
        message: Buffer.from(combinedBuffer).toString('hex') 
    };
}

async function SupraBuildPayload(types, values, additionalArgTypes) {
    const payload = types.map((type, index) => {
        console.log(type, values[index]);
        const value = values[index];
        return Serialize(type, value, additionalArgTypes);
    });

    return payload;
}

async function SupraSendTransaction(supraClient, signer, values, transaction, additionalArgTypes){
    // 1. Build the transaction data
    // ["0xAddress", "ModuleName", "FunctionName"]
    console.log("Payload:", values);
    const transactionData = await getFunctionData("supra", transaction);
    // 3. Build the payload with your specific serialization rules
    const txPayload = await SupraBuildPayload(transactionData.args, values, additionalArgTypes);

    // 4. Construct and send the transaction
    const senderAddr = signer.address();
    //console.log(supraClient);
    const accountInfo = await supraClient.getAccountInfo(senderAddr);
    
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
    //console.log("Fetching Supra Event:", event_name);
    let event = await getEventData("supra", event_name);
     //   console.log(event);
    const response = await fetch(`https://rpc-testnet.supra.com/rpc/v3/events/${event.event}`, {
        method: 'GET',
        headers: { "Accept": "*/*" },
    });
    
    let result = await response.json();
    console.log(result);
    // Map the raw RPC result to your desired format
    return result.data.map(item => ({
        hash: item.transaction_hash,
        block: item.block_height,
        data: item.event.data
    }));
}

async function getSupraView(path, args) {
    const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
         method: 'POST',
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            function: path,
            type_arguments: [],
            arguments: [args]
        })
    });
    const body = await response.json();
    return body.result[0];
}

module.exports = { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, getSupraAddress, fetchSupraEvent, test_SupraSendTransaction, getSupraView };