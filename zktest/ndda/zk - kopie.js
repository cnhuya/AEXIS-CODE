const { buildPoseidon, buildEddsa } = require("circomlibjs");

const { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, getSupraAddress } = require("../util/chains/supra_util");
const { getSuiAccFromPrivKey, SuiSign, getSuiClient } = require("../util/chains/sui_util");
const { getPrivKey } = require("../util/chains/global_util");
const { getEvmAccFromPrivKey, EvmSign } = require("../util/chains/evm_util");
const { prepareBatch } = require("./prover.js");

const path = require('path');
const fs = require("fs");
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const { ethers } = require("ethers");

const chainConfigs = {
    supra: { envKey: 'SUPRA_ACCOUNTS', initFunc: getSupraAccFromPrivKey, signFunc: SupraSign },
    sui: { envKey: 'SUI_ACCOUNTS', initFunc: getSuiAccFromPrivKey, signFunc: SuiSign },
    base: { envKey: 'BASE_ACCOUNTS', initFunc: getEvmAccFromPrivKey, signFunc: EvmSign }
};

let epoch = 0;
let wallets = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../config/wallets.json'), 'utf8'));
let data = {};

class PoseidonMerkleTree {
    constructor(leaves, poseidon, depth = 4) {
        this.poseidon = poseidon;
        const F = poseidon.F;
        this.depth = depth;
        this.nValidators = 8; 

        // 1. Pre-calculate Zero Hashes for every level
        // level 0: hash([0,0,0])
        // level 1: hash([level0, level0]) ...
        this.zeroHashes = new Array(depth + 1);
        this.zeroHashes[0] = F.toObject(this.poseidon([0, 0, 0]));
        for (let i = 1; i <= depth; i++) {
            this.zeroHashes[i] = F.toObject(this.poseidon([this.zeroHashes[i-1], this.zeroHashes[i-1]]));
        }

        // 2. Initial padding of raw leaves to nValidators
        let fullLeaves = [...leaves];
        while (fullLeaves.length < this.nValidators) {
            fullLeaves.push("0");
        }

        this.leaves = fullLeaves.map((v) => {
            if (v === "0") return this.zeroHashes[0];
            return F.toObject(this.poseidon([
                BigInt(v.pub_key_x), 
                BigInt(v.pub_key_y), 
                BigInt(v.staked)
            ]));
        });

        this.layers = []; 
        this.buildTree();
    }

    buildTree() {
        let currentLayer = this.leaves;
        this.layers.push(currentLayer);

        for (let d = 0; d < this.depth; d++) {
            let nextLayer = [];
            // We use the depth-specific zero hash if a sibling is missing
            for (let i = 0; i < currentLayer.length; i += 2) {
                const left = currentLayer[i];
                const right = (currentLayer[i + 1] !== undefined) 
                    ? currentLayer[i + 1] 
                    : this.zeroHashes[d]; // Use zero hash for THIS level
                
                const hash = this.poseidon([left, right]);
                nextLayer.push(this.poseidon.F.toObject(hash));
            }
            this.layers.push(nextLayer);
            currentLayer = nextLayer;
        }
    }

    generateProof(index) {
        let siblings = [];
        let indices = [];
        let currentIndex = index;

        for (let i = 0; i < this.depth; i++) {
            let layer = this.layers[i];
            let isRightNode = currentIndex % 2 === 1;
            let siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;

            // FIX: If sibling is missing, use the zeroHash for this level
            let sibling = (layer[siblingIndex] !== undefined) 
                ? layer[siblingIndex] 
                : this.zeroHashes[i];

            siblings.push(sibling);
            indices.push(isRightNode ? 1 : 0);
            currentIndex = Math.floor(currentIndex / 2);
        }
        return { siblings, indices };
    }

    getRoot() {
        return this.layers[this.depth][0];
    }
}



    async function deriveBabyJubKey(senderAcc, SignFunc) {
        console.log(senderAcc);
        const eddsa = await buildEddsa();

        // 2. The "Seed" Message
        const message = "Sign to initialize your Bridge Validator Key. \n\nThis will not cost any gas.";
        
        // 3. Convert message to Buffer for Supra's signBuffer
        const msgBuffer = Buffer.from(message);

        // 4. Get the ECDSA/EdDSA signature from the Supra Account
        // This signature is deterministic for the given msgBuffer
        const signature = await SignFunc(msgBuffer , senderAcc); 
        
        // 5. Hash the signature to get a 32-byte private key
        // Most ZK projects use Keccak256 or SHA256. 
        // If Supra SDK doesn't have a direct 'hash' util, ethers.keccak256 is fine.
        const sigBytes = signature.signedBytes ? signature.signedBytes : signature;
        const babyPrivKeyHex = ethers.keccak256(sigBytes.toString('hex')).slice(2);
        
        // 6. Convert hex string to Buffer for BabyJubJub
        babyPrivKey = Buffer.from(babyPrivKeyHex.slice(2), "hex");

        const pubKey = eddsa.prv2pub(babyPrivKey);
        return {
            privKey: babyPrivKeyHex,
            pubKeyX: eddsa.F.toObject(pubKey[0]).toString(),
            pubKeyY: eddsa.F.toObject(pubKey[1]).toString(),
        }

    }


function getChainAccounts(chain) {
    const config = chainConfigs[chain.toLowerCase()];   
    if (!config) {
        throw new Error(`Chain ${chain} not supported.`);
    }

    const rawJson = process.env[config.envKey];
    if (!rawJson) {
        console.warn(`⚠️ No environment variable found for ${config.envKey}`);
        return { config, accountMap: {} };
    }

    try {
        const accountMap = JSON.parse(rawJson);
        return { config, accountMap };
    } catch (e) {
        console.error(`❌ JSON Parse error in ${config.envKey}:`, e.message);
        return { config, accountMap: {} };
    }
}

async function registerValidatorAccount(client, accountName, privKey, config) {
    try {
        // 1. Initialize the L1 Signer
        const signer = await config.initFunc(privKey);

        // 2. Derive the BabyJubJub Key
        const babyJubData = await deriveBabyJubKey(signer, config.signFunc);
        
        // 3. Prepare ID (Full Integer)
        const randomId = Math.floor(Math.random() * 1000000).toString();

        const address = await getSupraAddress(signer);

        // 5. Send Transactions
        const payload1 = [address, address, randomId];
        await SupraSendTransaction(client, signer, payload1, "save_validator");

        const payload2 = [address, babyJubData.pubKeyX, babyJubData.pubKeyY];
        await SupraSendTransaction(client, signer, payload2, "register_parent");

        console.log(`✅ Derived & Saved key for [${accountName}]`);

        return {
            accountName,
            signer: signer.address(),
            ...babyJubData
        };
    } catch (err) {
        console.error(`❌ Detailed Error for [${accountName}]:`, err.message);
        if (err.data) {
            console.log("Additional Error Data:", JSON.stringify(err.data, null, 2));
        }
        return null; // Return null so the loop can continue
    }
}

async function validate(client, accountName, privKey, config) {
    try {

        // Ensure newValidatorRoot is BigInt
        let newValidatorRoot = await generateGenesisRoot(await get_validators());
        if (typeof newValidatorRoot === 'string') {
            newValidatorRoot = BigInt(newValidatorRoot);
        }
        
        data.newValidatorRoot = newValidatorRoot;

        const poseidon = await buildPoseidon();
        const CIRCUIT_N_VALIDATORS = 8; 
        const CIRCUIT_TREE_DEPTH = 4;   

            // 1. Build the Tree
        const validatorsForTree = data.validators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
            pub_key_x: BigInt(v.pub_key_x),
            pub_key_y: BigInt(v.pub_key_y),
            staked: BigInt(v.staked)
        }));
        const tree = new PoseidonMerkleTree(validatorsForTree, poseidon, CIRCUIT_TREE_DEPTH);
        data.tree = tree;
        const currentRoot = tree.getRoot(); 
        data.currentRoot = currentRoot;


        // 1. Initialize the L1 Signer
        const signer = await config.initFunc(privKey);

        // 2. Derive the BabyJubJub Key
        const babyJubData = await deriveBabyJubKey(signer, config.signFunc);

        const address = await getSupraAddress(signer);

        let signature = await signRotationMessage(babyJubData.privKey, data.currentRoot, data.newValidatorRoot, 0);

        const payload = [
            data.currentRoot.toString(),  // old_validator_root: String
            signature.r8x.toString(),     // s_r8x: String
            signature.r8y.toString(),     // s_r8y: String  
            signature.s.toString(),       // s: String
            signature.message.toString(),               // message: String ← This was missing!
        ];

        await SupraSendTransaction(client, signer, payload, "validate");

        console.log(`✅ Validation TX sent for [${accountName}]`);

        return {
            accountName,
            l1Address: signer.address || (signer.getPublicKey ? signer.getPublicKey().toSuiAddress() : "N/A"),
            ...babyJubData
        };
    } catch (err) {
        console.error(`❌ Detailed Error for (validation) [${accountName}]:`, err);
        if (err.data) {
            console.log("Additional Error Data:", JSON.stringify(err.data, null, 2));
        }
        return null; // Return null so the loop can continue
    }
}

/*async function get_epoch() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::genesisV1::return_epoch",
                type_arguments: [],
                arguments: []
            })
        });

        const body = await response.json();
        const epoch = body.result;

        return epoch;

    } catch (error) {
        console.error("Failed to fetch validators:", error);
        // Better to keep existing data on error rather than clearing it
        return data.validators || [];
    }
} */

async function get_validators() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::QiaraVv16::return_all_active_parents_full",
                type_arguments: [],
                arguments: []
            })
        });

        const body = await response.json();
        const validatorsData = body.result?.[0].data;

        if (!validatorsData) return data.validators || [];

        const validatorsArray = validatorsData.map(v => {
            // FIX: Use BigInt for addition to prevent precision loss on 18-decimal numbers
            const totalStaked = BigInt(v.value.self_staked || 0) + BigInt(v.value.total_stake || 0);
            
        return {
                address: v.key,
                staked: totalStaked.toString(), 
                pub_key_x: v.value.pub_key_x,
                pub_key_y: v.value.pub_key_y,
            };
        });

        validatorsArray.sort((a, b) => a.address.localeCompare(b.address));

        if (JSON.stringify(validatorsArray) === JSON.stringify(data.validators)) {
            return data.validators;
        }

        data.validators = validatorsArray;
        console.log("Validators Updated (Count):", validatorsArray.length);
        return validatorsArray;

    } catch (error) {
        console.error("Failed to fetch validators:", error);
        return data.validators || [];
    }
}



async function get_validators_signatures(old_root) {
    console.log(old_root);
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax23::return_state",
                type_arguments: [],
                arguments: [old_root.toString()]
            })
        });

        const body = await response.json();
        // 1. Handle explicit RPC errors
        if (body.error) {
            console.log("Error! Empty Singatures Data");
            return []; 
        }
        // 2. Safely access the data and provide a fallback empty array
        const validatorsData = body.result?.[0]?.parents?.data;
        // 3. Return empty early if no data exists to prevent .map() from crashing
        if (!validatorsData || !Array.isArray(validatorsData)) {
            console.log("Empty Singatures Data");
            return [];
        }

        
        const validatorsArray = validatorsData.map(v => {
            const totalStaked = BigInt(v.value.self_staked || 0) + BigInt(v.value.total_stake || 0);
            return {
                address: v.key,
                staked: totalStaked.toString(), 
                pub_key_x: v.value.pub_key_x,
                pub_key_y: v.value.pub_key_y,
                message: v.value.message,  // ← This should now exist!
                s: v.value.s,
                s_r8x: v.value.s_r8x,
                s_r8y: v.value.s_r8y,
                index: v.value.index
            };
        });

        validatorsArray.sort((a, b) => a.address.localeCompare(b.address));

        // Ensure global/outer 'data' object is updated if it exists
        if (typeof data !== 'undefined' && data.validators_sig != validatorsArray) {
            console.log("New Signatures Data! Generating Input...");
            data.validators_sig = validatorsArray;
            await build_input();
        }
        console.log("RPC returned signature data:");
        console.log(JSON.stringify(validatorsArray[0], null, 2));
        return validatorsArray;

    } catch (error) {
        // Suppress logging if you want it completely silent, or keep as a minor trace
        if (typeof data !== 'undefined') {
            data.validators_sig = [];
        }
        return [];
    }
}

async function generateGenesisRoot(validators) {
    const poseidon = await buildPoseidon();
    const F = poseidon.F;
    
    // 1. Sort validators (CRITICAL: Must match circuit sorting)
    const sortedVals = [...validators].sort((a, b) => a.address.localeCompare(b.address));
    const nValidators = 8; // Fixed circuit size

    // 2. Calculate REAL leaves
    const leaves = sortedVals.slice(0, nValidators).map(val => {
        return poseidon([
            BigInt(val.pub_key_x), 
            BigInt(val.pub_key_y), 
            BigInt(val.staked)
        ]);
    });

    // 3. Pad with Zero Hashes (Poseidon(0,0,0))
    const zeroLeaf = poseidon([0, 0, 0]);
    while (leaves.length < nValidators) {
        leaves.push(zeroLeaf);
    }

    // 4. Build Merkle Tree
    let currentLevel = leaves;
    while (currentLevel.length > 1) {
        let nextLevel = [];
        for (let i = 0; i < currentLevel.length; i += 2) {
            const left = currentLevel[i];
            const right = (i + 1 < currentLevel.length) ? currentLevel[i+1] : zeroLeaf;
            nextLevel.push(poseidon([left, right]));
        }
        currentLevel = nextLevel;
    }

    return F.toObject(currentLevel[0]); // Return BigInt, not string
}

async function signRotationMessage(babyPrivKey, currentValidatorRoot, newValidatorRoot, epoch) {
    const eddsa = await buildEddsa();
    const poseidon = await buildPoseidon();
    const F = poseidon.F;
    // Convert everything to BigInt to be safe
    const currentRootBigInt = BigInt(currentValidatorRoot);
    const newRootBigInt = BigInt(newValidatorRoot);
    const epochBigInt = BigInt(epoch);

    console.log("Signing message with:");
    console.log("Current Root:", currentRootBigInt.toString());
    console.log("New Root:", newRootBigInt.toString());
    console.log("Epoch:", epochBigInt.toString());

    const msgHash = poseidon([
        currentRootBigInt, 
        newRootBigInt, 
        epochBigInt
    ]);

    // 2. Sign the message
    const signature = eddsa.signPoseidon(babyPrivKey, msgHash);
    
    return {
    
        r8x: eddsa.F.toObject(signature.R8[0]).toString(),
        r8y: eddsa.F.toObject(signature.R8[1]).toString(),
        s: signature.S.toString(),
        isSigned: 1,
        message: F.toObject(msgHash).toString()
    };
}


async function build_input() {
    try {
        const poseidon = await buildPoseidon();
        const eddsa = await buildEddsa();
        const F = poseidon.F;
        const CIRCUIT_N_VALIDATORS = 8;
        
        if (!data.tree) {
            console.error("Tree not initialized. Skipping input build.");
            return;
        }

        const sortedValidators = [...data.validators].sort((a, b) => 
            a.address.localeCompare(b.address)
        );

        console.log("Sorted validators:");
        console.log(sortedValidators);

        const currentRootStr = data.currentRoot.toString();
        const newRootStr = data.newValidatorRoot.toString();
        const epochStr = epoch.toString();

        const inputs = {
            currentValidatorRoot: currentRootStr,
            newValidatorRoot: newRootStr,
            epoch: epochStr,
            validatorPubKeysX: [],
            validatorPubKeysY: [],
            validatorStakes: [],
            isSigned: [],
            signaturesR8x: [],
            signaturesR8y: [],
            signaturesS: [],
            valPathElements: [],
            valPathIndices: []
        };

        // Construct Message Hash
        const msgHash = poseidon([
            BigInt(currentRootStr), 
            BigInt(newRootStr), 
            BigInt(epochStr)
        ]);

    console.log("\n=== VERIFICATION DEBUG ===");
    console.log("Verifying with:");
    console.log("Current Root:", currentRootStr);
    console.log("New Root:", newRootStr);
    console.log("Epoch:", epochStr);
    console.log("Message Hash (decimal):", F.toObject(msgHash).toString());
    console.log("Message Hash (hex):", F.toObject(msgHash).toString(16));

        const sigMap = new Map();
        if (data.validators_sig) {
            data.validators_sig.forEach(sig => {
                // Use address as the key, ensure lowercase for safety
                if (sig.address) {
                    sigMap.set(sig.address.toLowerCase(), sig);
                }
            });
        }
        console.log("DEBUG: Local New Root matches RPC data?");
        const rpcSigSample = data.validators_sig[0];
        if (rpcSigSample) {
            console.log("RPC Sample:");
            console.log(rpcSigSample);
            console.log("Local Sample:");
            console.log(sigMap.get(rpcSigSample.address.toLowerCase()));
        }
        console.log("Signatures:", sigMap);
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            const v = sortedValidators[i];
            let sig = v ? sigMap.get(v.address.toLowerCase()) : null;
            
            if (v) {
                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked.toString());
                
                let isValidSignature = false;
                
                if (sig) {
                    try {
                        // DEBUG: Log the raw values from RPC for the first validator
                        if (i === 0) {
                            console.log(`[RPC Raw] R8x: ${sig.s_r8x} | R8y: ${sig.s_r8y} | S: ${sig.s}`);
                        }

                        const sigObj = {
                            R8: [F.e(sig.s_r8x), F.e(sig.s_r8y)],
                            S: BigInt(sig.s)
                        };
                        const pubKey = [F.e(v.pub_key_x), F.e(v.pub_key_y)];
                        
                        isValidSignature = eddsa.verifyPoseidon(msgHash, sigObj, pubKey);
                        
                        if (!isValidSignature) {
                            console.warn(`⚠️ Sig Fail ${v.address.slice(0,6)}: RPC sig does not match Message Hash.`);
                        } else {
                            console.log(`✅ Sig Verified for ${v.address.slice(0,6)}`);
                        }
                    } catch (e) {
                        console.error(`Error checking sig for ${v.address}:`, e.message);
                    }
                }

                if (isValidSignature) {
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    inputs.isSigned.push(0);
                    inputs.signaturesR8x.push("0");
                    inputs.signaturesR8y.push("1");
                    inputs.signaturesS.push("0");
                }
            } else {
                // Padding
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("1");
                inputs.validatorStakes.push("0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("1");
                inputs.signaturesS.push("0");
            }

            const proof = data.tree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));
        }

        const fs = require('fs');
        fs.writeFileSync("./input.json", JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready.");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

async function runInitialization(client,chain) {
    const { config, accountMap } = getChainAccounts(chain);
    const results = [];

    for (const [accountName, privKey] of Object.entries(accountMap)) {
        const result = await registerValidatorAccount(client, accountName, privKey, config);
        if (result) results.push(result);
    }

    return results;
}

async function runValidation(client, chain) {
    const { config, accountMap } = getChainAccounts(chain);

    for (const [accountName, privKey] of Object.entries(accountMap)) {
        await validate(client, accountName, privKey, config);
    }
}

async function prepare() {
    try {
        const result = await prepareBatch();
        
        console.log("\n--- Proof from prepareBatch ---");
        console.log("pA:", result.pA);
        console.log("pB:", result.pB);
        console.log("pC:", result.pC);
        console.log("publicSignals:", result.publicSignals);

        data.result = result;
    } catch (err) {
        console.error("Error generating proof:", err);
    }
}

async function main() {
    const walletsPath = path.resolve(__dirname, '../config/wallets.json');
    const outputPath = path.resolve(__dirname, './validator_keys.json');

    try {
        console.log("Checking if wallets inputs changed...");
        
        let new_wallets = JSON.parse(fs.readFileSync(walletsPath, 'utf8'));
        const walletsChanged = JSON.stringify(wallets) !== JSON.stringify(new_wallets);
        const keysFileMissing = !fs.existsSync(outputPath);

        if (walletsChanged || keysFileMissing) {
            wallets = new_wallets;
            console.log("🚀 Starting Validator Key Generation...");
            const validatorData = await runInitialization(await getSupraClient("https://rpc-testnet.supra.com"), 'supra');
            fs.writeFileSync(outputPath, JSON.stringify(validatorData, null, 4));
            console.log(`✅ Success! Keys saved to: ${outputPath}`);
        }

    /*if (epoch == 0) {
            console.log(`New Epoch detected: ${epoch}`);

            // 1. Refresh validator list
            const currentValidators = await get_validators();
            data.validators = currentValidators;
            
            // 2. Rebuild the tree
            const poseidon = await buildPoseidon();
            data.tree = new PoseidonMerkleTree(currentValidators, poseidon, 4);
            data.currentRoot = data.tree.getRoot(); // BigInt

            // 3. Calculate New Root as BigInt
            console.log("Calculating consistent New Root for signatures...");
            const consistentNewRoot = await generateGenesisRoot(data.validators);
            data.newValidatorRoot = consistentNewRoot; // Now this is BigInt
            console.log("🎯 Target New Root:", consistentNewRoot.toString());

            // 4. Validate - Now all parameters are correct types
            await runValidation(await getSupraClient("https://rpc-testnet.supra.com"), 'supra');

            // 5. Fetch those signatures back from the RPC/State
            await get_validators_signatures(data.currentRoot);

            // 6. Build circuit input and prove
            await build_input(); 
            await prepare();
        }*/

    } catch (error) {
        console.error("Critical failure in main:", error);
    }
}

async function deepDebugSignature() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const F = poseidon.F;
    const babyJub = eddsa.babyJub;
    
    // Direct values from RPC
    const R8x = "12625747389180416900121815497740837991694099430167341955701898244038203638663";
    const R8y = "17162106509655329764313065589618098119892392676664955789589105787395508492818";
    const S = "2051324057756154161129476395528013349129790360425143494890911774757497005849";
    const pubKeyX = "18051279112200792413495343664571214296972048672439013273320924987043950742805";
    const pubKeyY = "17053456987589277199210708744947909825202131766180429682893967893434274831405";
    const message = "18078936504211808466860709183645494262497462851826908942269902289567999316851";
    
    console.log("\n=== DEEP SIGNATURE DEBUG ===");
    
    // 1. Verify field element conversions
    console.log("\n1. Field Element Checks:");
    const R8x_fe = F.e(R8x);
    const R8y_fe = F.e(R8y);
    const S_fe = BigInt(S);
    const pkX_fe = F.e(pubKeyX);
    const pkY_fe = F.e(pubKeyY);
    const msg_fe = F.e(message);
    
    console.log("R8x (FE):", F.toString(R8x_fe));
    console.log("R8y (FE):", F.toString(R8y_fe));
    console.log("S:", S_fe.toString());
    console.log("PKx (FE):", F.toString(pkX_fe));
    console.log("PKy (FE):", F.toString(pkY_fe));
    console.log("Msg (FE):", F.toString(msg_fe));
    
    // 2. Check if R8 is a valid point on BabyJubJub curve
    console.log("\n2. Curve Point Validation:");
    // Use babyJub.inCurve instead of eddsa.inCurve
    const isValidPoint = babyJub.inCurve([R8x_fe, R8y_fe]);
    console.log("Is R8 a valid curve point?", isValidPoint);
    
    // 3. Check if public key is valid
    const isValidPK = babyJub.inCurve([pkX_fe, pkY_fe]);
    console.log("Is Public Key valid?", isValidPK);
    
    // 4. Manual verification (step-by-step)
    console.log("\n3. Manual Verification Steps:");
    
    // Step 1: A = S * G + R8
    const G = babyJub.Base8;
    console.log("Generator G:", G.map(g => F.toString(g)));
    
    // S * G
    const SG = babyJub.mulPointEscalar(G, S_fe);
    console.log("S * G:", SG.map(p => F.toString(p)));
    
    // S * G + R8
    const A = babyJub.addPoint(SG, [R8x_fe, R8y_fe]);
    console.log("S * G + R8:", A.map(p => F.toString(p)));
    
    // Step 2: B = message * PK + R8
    const mPK = babyJub.mulPointEscalar([pkX_fe, pkY_fe], F.toObject(msg_fe));
    console.log("message * PK:", mPK.map(p => F.toString(p)));
    
    const B = babyJub.addPoint(mPK, [R8x_fe, R8y_fe]);
    console.log("message * PK + R8:", B.map(p => F.toString(p)));
    
    // Step 3: Check if A == B
    const areEqual = F.eq(A[0], B[0]) && F.eq(A[1], B[1]);
    console.log("\n4. Final Check (A == B)?", areEqual);
    console.log("A[0] vs B[0]:", F.toString(A[0]), "==", F.toString(B[0]), "?", F.eq(A[0], B[0]));
    console.log("A[1] vs B[1]:", F.toString(A[1]), "==", F.toString(B[1]), "?", F.eq(A[1], B[1]));
    
    // 5. Try the library verification
    console.log("\n5. Library Verification:");
    const sigObj = { R8: [R8x_fe, R8y_fe], S: S_fe };
    const pubKey = [pkX_fe, pkY_fe];
    
    try {
        const result = eddsa.verifyPoseidon(msg_fe, sigObj, pubKey);
        console.log("eddsa.verifyPoseidon result:", result);
    } catch (e) {
        console.log("Error in verifyPoseidon:", e.message);
        console.log("Error stack:", e.stack);
    }
    
    // 6. Check if message is in proper range
    console.log("\n6. Message Range Check:");
    const msgBigInt = BigInt(message);
    const curveOrder = babyJub.order;
    console.log("Message:", msgBigInt.toString());
    console.log("Curve order (scalar field):", curveOrder.toString());
    console.log("Message < order?", msgBigInt < curveOrder);
    
    // 7. Try with message reduced mod order
    const msgReduced = msgBigInt % curveOrder;
    const msg_fe_reduced = F.e(msgReduced.toString());
    console.log("Reduced message:", msgReduced.toString());
    
    console.log("\n7. Verification with reduced message:");
    try {
        const resultReduced = eddsa.verifyPoseidon(msg_fe_reduced, sigObj, pubKey);
        console.log("Result with reduced message:", resultReduced);
    } catch (e) {
        console.log("Error:", e.message);
    }
    
    // 8. Check signature format - maybe S needs to be reduced too
    console.log("\n8. Signature S range check:");
    const scalarField = babyJub.subOrder; // Usually the scalar field for S
    console.log("S value:", S_fe.toString());
    console.log("Scalar field order:", scalarField.toString());
    console.log("S < scalar field order?", S_fe < scalarField);
    
    // Try reducing S
    const S_reduced = S_fe % scalarField;
    console.log("Reduced S:", S_reduced.toString());
    
    const sigObjReduced = { R8: [R8x_fe, R8y_fe], S: S_reduced };
    console.log("Verification with reduced S:");
    try {
        const result = eddsa.verifyPoseidon(msg_fe, sigObjReduced, pubKey);
        console.log("Result:", result);
    } catch (e) {
        console.log("Error:", e.message);
    }
}

async function debugSignatureCreation() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const F = poseidon.F;
    
    // Simulate what happens in validate()
    const currentRoot = "15755186352962320951938047110167524248076012371854770923076722497551360052142";
    const newRoot = "20690548743538681487328453848416498401133703029078800785107007752718117675839";
    const epoch = "0";
    
    // Create a test private key
    const testPrivKey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const privKeyBuffer = Buffer.from(testPrivKey, "hex");
    
    console.log("\n=== SIGNATURE CREATION DEBUG ===");
    
    // 1. Create message hash
    const msgHash = poseidon([
        BigInt(currentRoot), 
        BigInt(newRoot), 
        BigInt(epoch)
    ]);
    
    console.log("Message hash:", F.toObject(msgHash).toString());
    
    // 2. Derive public key
    const pubKey = eddsa.prv2pub(privKeyBuffer);
    console.log("Public Key X:", F.toObject(pubKey[0]).toString());
    console.log("Public Key Y:", F.toObject(pubKey[1]).toString());
    
    // 3. Sign
    const signature = eddsa.signPoseidon(privKeyBuffer, msgHash);
    console.log("\nGenerated Signature:");
    console.log("R8x:", F.toObject(signature.R8[0]).toString());
    console.log("R8y:", F.toObject(signature.R8[1]).toString());
    console.log("S:", signature.S.toString());
    
    // 4. Verify immediately
    const isValid = eddsa.verifyPoseidon(msgHash, signature, pubKey);
    console.log("\nSelf-verification result:", isValid);
    
    // 5. Check signature format
    console.log("\nSignature object structure:");
    console.log("Type of R8:", Array.isArray(signature.R8));
    console.log("R8 length:", signature.R8.length);
    console.log("Type of S:", typeof signature.S);
    
    return { signature, pubKey, msgHash };
}
async function findCorrectS() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const F = poseidon.F;
    const babyJub = eddsa.babyJub;
    
    // Values from RPC
    const R8x = "12625747389180416900121815497740837991694099430167341955701898244038203638663";
    const R8y = "17162106509655329764313065589618098119892392676664955789589105787395508492818";
    const S_wrong = "2051324057756154161129476395528013349129790360425143494890911774757497005849";
    const pubKeyX = "18051279112200792413495343664571214296972048672439013273320924987043950742805";
    const pubKeyY = "17053456987589277199210708744947909825202131766180429682893967893434274831405";
    const message = "18078936504211808466860709183645494262497462851826908942269902289567999316851";
    
    console.log("\n=== FINDING CORRECT S VALUE ===");
    
    const R = [F.e(R8x), F.e(R8y)];
    const PK = [F.e(pubKeyX), F.e(pubKeyY)];
    const m = F.e(message);
    
    // 1. Calculate m·PK
    const mPK = babyJub.mulPointEscalar(PK, F.toObject(m));
    console.log("m·PK:", mPK.map(p => F.toString(p)));
    
    // 2. Calculate R + m·PK
    const R_plus_mPK = babyJub.addPoint(R, mPK);
    console.log("R + m·PK:", R_plus_mPK.map(p => F.toString(p)));
    
    // 3. We need to find S such that: S·G = R + m·PK
    const G = babyJub.Base8;
    const SG_wrong = babyJub.mulPointEscalar(G, BigInt(S_wrong));
    console.log("\nS·G (with wrong S):", SG_wrong.map(p => F.toString(p)));
    console.log("Should equal:", R_plus_mPK.map(p => F.toString(p)));
    
    // 4. Check if points are equal
    const areEqual = F.eq(SG_wrong[0], R_plus_mPK[0]) && F.eq(SG_wrong[1], R_plus_mPK[1]);
    console.log("\nAre they equal?", areEqual);
    
    // 5. Try to brute force find correct S (small range)
    console.log("\n=== BRUTE FORCE SEARCH FOR S ===");
    const S_big = BigInt(S_wrong);
    const L = babyJub.order;
    
    // Search in wider range
    for (let i = -100; i <= 100; i++) {
        if (i === 0) continue;
        const S_test = (S_big + BigInt(i) + L) % L;
        const SG_test = babyJub.mulPointEscalar(G, S_test);
        
        if (F.eq(SG_test[0], R_plus_mPK[0]) && F.eq(SG_test[1], R_plus_mPK[1])) {
            console.log(`✅ FOUND CORRECT S! Offset ${i}: ${S_test.toString()}`);
            console.log(`Given S (wrong): ${S_wrong}`);
            console.log(`Correct S: ${S_test.toString()}`);
            console.log(`Difference: ${i}`);
            
            // Test verification with corrected S
            const sigObj = { 
                R8: [F.e(R8x), F.e(R8y)], 
                S: S_test 
            };
            const pubKey = [F.e(pubKeyX), F.e(pubKeyY)];
            const msg_fe = F.e(message);
            
            const isValid = eddsa.verifyPoseidon(msg_fe, sigObj, pubKey);
            console.log(`Verification with corrected S: ${isValid}`);
            
            return S_test;
        }
    }
    
    console.log("No S found in range [-100, +100]");
    
    // 6. Maybe the entire signature is for a DIFFERENT public key
    console.log("\n=== CHECKING SIGNATURE CONSISTENCY ===");
    
    // The signature equation is: S = r + H(R, PK, m) * s mod L
    // If S is wrong, maybe PK is wrong?
    
    // Let's check what public key WOULD verify with given R, S, m
    // We have: S·G = R + m·PK
    // So: m·PK = S·G - R
    // And: PK = (m⁻¹)·(S·G - R)
    
    // Calculate S·G
    const SG = babyJub.mulPointEscalar(G, BigInt(S_wrong));
    
    // Calculate -R (negative of R)
    // For ed25519: -(x,y) = (-x, y) but in BabyJubJub it might be different
    // Actually for twisted Edwards: -(x,y) = (-x, y)
    const negR = [F.neg(R[0]), R[1]]; // Assuming twisted Edwards
    
    // Calculate S·G - R = S·G + (-R)
    const SG_minus_R = babyJub.addPoint(SG, negR);
    console.log("S·G - R:", SG_minus_R.map(p => F.toString(p)));
    
    // Now PK = (m⁻¹)·(S·G - R)
    const m_inv = F.inv(m);
    const m_inv_bigint = F.toObject(m_inv);
    
    const PK_calculated = babyJub.mulPointEscalar(SG_minus_R, m_inv_bigint);
    console.log("\nCalculated PK (that would verify):");
    console.log("X:", F.toString(PK_calculated[0]));
    console.log("Y:", F.toString(PK_calculated[1]));
    
    console.log("\nActual PK from RPC:");
    console.log("X:", F.toString(PK[0]));
    console.log("Y:", F.toString(PK[1]));
    
    console.log("\nDo they match?");
    console.log("X:", F.eq(PK_calculated[0], PK[0]));
    console.log("Y:", F.eq(PK_calculated[1], PK[1]));
    
    // 7. Try the other negation
    console.log("\n=== TRYING DIFFERENT NEGATION ===");
    const negR2 = [F.neg(R[0]), F.neg(R[1])];
    const SG_minus_R2 = babyJub.addPoint(SG, negR2);
    const PK_calculated2 = babyJub.mulPointEscalar(SG_minus_R2, m_inv_bigint);
    
    console.log("Alternative calculated PK:");
    console.log("X:", F.toString(PK_calculated2[0]));
    console.log("Y:", F.toString(PK_calculated2[1]));
    
    return null;
}

async function testActualSignature() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const F = poseidon.F;
    
    // Test with acc4 (which should be validator 0xd4fc...)
    const config = getChainAccounts('supra').config;
    const acc4PrivKey = JSON.parse(process.env.SUPRA_ACCOUNTS)['acc4'];
    const acc4Signer = await config.initFunc(acc4PrivKey);
    const acc4Address = await getSupraAddress(acc4Signer);
    
    console.log("\n=== TESTING ACC4 ===");
    console.log("acc4 address:", acc4Address);
    console.log("Expected validator address: 0xd4fcdba413ff103eec996a07b795847a8b4ce5c328d35d9843dc5ec2230de605");
    console.log("Match?", acc4Address === "0xd4fcdba413ff103eec996a07b795847a8b4ce5c328d35d9843dc5ec2230de605");
    
    // Get acc4's BabyJub data
    const acc4BabyJub = await deriveBabyJubKey(acc4Signer, config.signFunc);
    console.log("\nacc4 BabyJub pubKeyX:", acc4BabyJub.pubKeyX);
    console.log("Validator 0xd4fc... pubKeyX: 18051279112200792413495343664571214296972048672439013273320924987043950742805");
    console.log("Match?", acc4BabyJub.pubKeyX === "18051279112200792413495343664571214296972048672439013273320924987043950742805");
    
    // Now test the signature
    const message = "18078936504211808466860709183645494262497462851826908942269902289567999316851";
    const R8x = "12625747389180416900121815497740837991694099430167341955701898244038203638663";
    const R8y = "17162106509655329764313065589618098119892392676664955789589105787395508492818";
    const S = "2051324057756154161129476395528013349129790360425143494890911774757497005849";
    
    const sig = {
        R8: [F.e(R8x), F.e(R8y)],
        S: BigInt(S)
    };
    
    const pubKey = [F.e(acc4BabyJub.pubKeyX), F.e(acc4BabyJub.pubKeyY)];
    const msg_fe = F.e(message);
    
    const result = eddsa.verifyPoseidon(msg_fe, sig, pubKey);
    console.log("\nSignature verification with acc4's key:", result);
    
    return result;
}

async function debugSignatureCreationAndStorage() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const F = poseidon.F;
    
    // Get acc4 data
    const config = getChainAccounts('supra').config;
    const acc4PrivKey = JSON.parse(process.env.SUPRA_ACCOUNTS)['acc4'];
    const acc4Signer = await config.initFunc(acc4PrivKey);
    
    // Get BabyJub private key (hex string)
    const babyJubData = await deriveBabyJubKey(acc4Signer, config.signFunc);
    const babyPrivKeyHex = babyJubData.babyPrivKey;
    const babyPrivKeyBuffer = Buffer.from(babyPrivKeyHex, "hex");
    
    console.log("\n=== SIGNATURE CREATION DEBUG ===");
    
    // Same parameters as before
    const currentRoot = "15755186352962320951938047110167524248076012371854770923076722497551360052142";
    const newRoot = "20690548743538681487328453848416498401133703029078800785107007752718117675839";
    const epoch = "0";
    
    // Create message hash
    const msgHash = poseidon([
        BigInt(currentRoot), 
        BigInt(newRoot), 
        BigInt(epoch)
    ]);
    
    const msgHashStr = F.toObject(msgHash).toString();
    console.log("Message hash:", msgHashStr);
    
    // Sign the message
    const signature = eddsa.signPoseidon(babyPrivKeyBuffer, msgHash);
    
    console.log("\nGenerated Signature:");
    console.log("R8x:", F.toObject(signature.R8[0]).toString());
    console.log("R8y:", F.toObject(signature.R8[1]).toString());
    console.log("S:", signature.S.toString());
    
    // Verify immediately
    const pubKey = eddsa.prv2pub(babyPrivKeyBuffer);
    const isValid = eddsa.verifyPoseidon(msgHash, signature, pubKey);
    console.log("\nSelf-verification:", isValid);
    
    // Compare with RPC data
    console.log("\n=== COMPARISON WITH RPC DATA ===");
    const rpcR8x = "12625747389180416900121815497740837991694099430167341955701898244038203638663";
    const rpcR8y = "17162106509655329764313065589618098119892392676664955789589105787395508492818";
    const rpcS = "2051324057756154161129476395528013349129790360425143494890911774757497005849";
    
    console.log("R8x match?", F.toObject(signature.R8[0]).toString() === rpcR8x);
    console.log("R8y match?", F.toObject(signature.R8[1]).toString() === rpcR8y);
    console.log("S match?", signature.S.toString() === rpcS);
    
    console.log("\nYour generated:");
    console.log("R8x:", F.toObject(signature.R8[0]).toString());
    console.log("R8y:", F.toObject(signature.R8[1]).toString());
    console.log("S:", signature.S.toString());
    
    console.log("\nRPC stored:");
    console.log("R8x:", rpcR8x);
    console.log("R8y:", rpcR8y);
    console.log("S:", rpcS);
    
    // Try to verify RPC signature with your key
    const rpcSig = {
        R8: [F.e(rpcR8x), F.e(rpcR8y)],
        S: BigInt(rpcS)
    };
    
    const rpcIsValid = eddsa.verifyPoseidon(msgHash, rpcSig, pubKey);
    console.log("\nRPC signature verification with your key:", rpcIsValid);
    
    // Check if maybe the signature is swapped?
    console.log("\n=== CHECKING FOR SWAPPED VALUES ===");
    
    // Try swapping R8x and R8y
    const swappedSig1 = {
        R8: [F.e(rpcR8y), F.e(rpcR8x)], // Swapped!
        S: BigInt(rpcS)
    };
    console.log("With swapped R8x/R8y:", eddsa.verifyPoseidon(msgHash, swappedSig1, pubKey));
    
    // Try different S values (maybe off by 1?)
    for (let i = -3; i <= 3; i++) {
        if (i === 0) continue;
        const testS = (BigInt(rpcS) + BigInt(i)).toString();
        const testSig = {
            R8: [F.e(rpcR8x), F.e(rpcR8y)],
            S: BigInt(testS)
        };
        const testResult = eddsa.verifyPoseidon(msgHash, testSig, pubKey);
        if (testResult) {
            console.log(`✅ Found correct S! Offset ${i}: ${testS}`);
        }
    }
}

async function testSignatureVerification() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const F = poseidon.F;
    
    // Test with RPC data for validator 0xd4fc...
    const currentRoot = "15755186352962320951938047110167524248076012371854770923076722497551360052142";
    const newRoot = "20690548743538681487328453848416498401133703029078800785107007752718117675839";
    const epoch = "0";
    
    // These are from RPC for validator 0xd4fc...
    const message = "18078936504211808466860709183645494262497462851826908942269902289567999316851";
    const pubKeyX = "18051279112200792413495343664571214296972048672439013273320924987043950742805";
    const pubKeyY = "17053456987589277199210708744947909825202131766180429682893967893434274831405";
    const R8x = "12625747389180416900121815497740837991694099430167341955701898244038203638663";
    const R8y = "17162106509655329764313065589618098119892392676664955789589105787395508492818";
    const S = "2051324057756154161129476395528013349129790360425143494890911774757497005849";
    
    console.log("\n=== TESTING SIGNATURE VERIFICATION ===");
    
    // Test the RPC signature
    const sig = {
        R8: [F.e(R8x), F.e(R8y)],
        S: BigInt(S)
    };
    
    const pubKey = [F.e(pubKeyX), F.e(pubKeyY)];
    
    console.log("\n1. Testing RPC signature with validator public key...");
    const msgBigInt = F.e(message);
    const result = eddsa.verifyPoseidon(msgBigInt, sig, pubKey);
    console.log("Result:", result);
    
    // Now let's check what public key YOU'RE actually using
    console.log("\n2. Checking YOUR BabyJub public key derivation...");
    
    // You need to check what BabyJub public key YOUR `acc4` generates
    // This requires your acc4 private key
    const config = getChainAccounts('supra').config;
    const acc4PrivKey = JSON.parse(process.env.SUPRA_ACCOUNTS)['acc4'];
    const yourSigner = await config.initFunc(acc4PrivKey);
    const yourBabyJubData = await deriveBabyJubKey(yourSigner, config.signFunc);
    
    console.log("Your BabyJub public key:");
    console.log("X:", yourBabyJubData.pubKeyX);
    console.log("Y:", yourBabyJubData.pubKeyY);
    console.log("\nValidator public key (from RPC):");
    console.log("X:", pubKeyX);
    console.log("Y:", pubKeyY);
    
    console.log("\nDo they match?");
    console.log("X:", yourBabyJubData.pubKeyX === pubKeyX);
    console.log("Y:", yourBabyJubData.pubKeyY === pubKeyY);
    
    // 3. Test if the signature verifies with YOUR public key
    console.log("\n3. Testing with YOUR public key...");
    const yourPubKey = [F.e(yourBabyJubData.pubKeyX), F.e(yourBabyJubData.pubKeyY)];
    const resultWithYourKey = eddsa.verifyPoseidon(msgBigInt, sig, yourPubKey);
    console.log("Verifies with YOUR key?", resultWithYourKey);
    
    // 4. The REAL problem: You need to sign with the validator's actual private key
    console.log("\n4. THE REAL PROBLEM:");
    console.log("- Validators have registered BabyJub public keys on-chain");
    console.log("- You're signing with YOUR test account keys (acc1, acc2, etc.)");
    console.log("- But those derive DIFFERENT BabyJub public keys!");
    console.log("- So signatures don't match the validator public keys!");
    
    return result;
}

main();
//deepDebugSignature();
//debugSignatureCreation();
//findCorrectS();
module.exports = { main };
