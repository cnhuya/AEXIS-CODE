const fs = require("fs");
const path = require("path");

async function build_input(type, data) {
    if (!data) {
        console.log("No data provided for input building.");
        return;
    }

    console.log("Building input for type:", type);

    if (type === "validators") {
        await build_validators_input(data);
    } else if (type === "balances") {
        await build_balances_input(data);
    } else if (type === "variables") {
        await build_variables_input(data);
    } else {
        console.log("Unsupported input build type:", type);
    }
}

async function build_validators_input(data) {
    try {
        const CIRCUIT_N_VALIDATORS = 8;
        
        if (!data.tree) {
            console.error("Tree not initialized. Skipping input build.");
            return;
        }

        const inputs = {
            currentValidatorRoot: data.currentRoot.toString(),
            newValidatorRoot: data.newValidatorRoot.toString(),
            epoch: data.epoch,
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

        // 1. Create a Signature Map using the PubKey as the key
        // Format: "pubKeyX_pubKeyY"
        const sigMap = {};
        //console.log("sigs:", data.validators_sig);
        if (data.validators_sig) {
            data.validators_sig.forEach(sig => {
                const key = `${sig.pub_key_x.toString()}_${sig.pub_key_y.toString()}`;
                sigMap[key] = sig;
            });
        }

        // 2. Iterate through the validators list (the ones in the Merkle Tree)
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            // Generate Merkle proof for this position
            const proof = data.tree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const v = data.validators[i];

            if (v) {
                // Construct the key to look up the signature
                const lookupKey = `${v.pub_key_x.toString()}_${v.pub_key_y.toString()}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked.toString());

                if (sig) {
                    // Match found: this validator signed
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    // No signature found for this pubkey
                    inputs.isSigned.push(0);
                    inputs.signaturesR8x.push("0");
                    inputs.signaturesR8y.push("0");
                    inputs.signaturesS.push("0");
                }
            } else {
                // Empty slot in the validator set
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.validatorStakes.push("0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("0");
                inputs.signaturesS.push("0");
            }
        }

        const inputPath = path.join(__dirname, '../../zk/validators/input.json');
        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready (Matched via PubKeys)");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

async function build_balances_input(data) {
    try {
        const CIRCUIT_N_VALIDATORS = 8;
        
        if (!data.tree) {
            console.error("Tree not initialized. Skipping input build.");
            return;
        }

        const inputs = {
            currentValidatorRoot: data.currentRoot.toString(),
            newValidatorRoot: data.newValidatorRoot.toString(),
            epoch: data.epoch,
            threshold: "2",
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

        // 1. Create a Signature Map using the PubKey as the key
        // Format: "pubKeyX_pubKeyY"
        const sigMap = {};
        console.log("sigs:", data.validators_sig);
        if (data.validators_sig) {
            data.validators_sig.forEach(sig => {
                const key = `${sig.pub_key_x.toString()}_${sig.pub_key_y.toString()}`;
                sigMap[key] = sig;
            });
        }

        // 2. Iterate through the validators list (the ones in the Merkle Tree)
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            // Generate Merkle proof for this position
            const proof = data.tree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const v = data.validators[i];

            if (v) {
                // Construct the key to look up the signature
                const lookupKey = `${v.pub_key_x.toString()}_${v.pub_key_y.toString()}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked.toString());

                if (sig) {
                    // Match found: this validator signed
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    // No signature found for this pubkey
                    inputs.isSigned.push(0);
                    inputs.signaturesR8x.push("0");
                    inputs.signaturesR8y.push("0");
                    inputs.signaturesS.push("0");
                }
            } else {
                // Empty slot in the validator set
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.validatorStakes.push("0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("0");
                inputs.signaturesS.push("0");
            }
        }

        const fs = require('fs');
        const inputPath = path.join(__dirname, '../zk/validators/input.json');
        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready (Matched via PubKeys)");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

async function build_variables_input(data) {
    try {
        const CIRCUIT_N_VALIDATORS = 8;
        
        if (!data.tree) {
            console.error("Tree not initialized. Skipping input build.");
            return;
        }

        const inputs = {
            currentValidatorRoot: data.currentRoot.toString(),
            newValidatorRoot: data.newValidatorRoot.toString(),
            epoch: data.epoch,
            threshold: "2",
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

        // 1. Create a Signature Map using the PubKey as the key
        // Format: "pubKeyX_pubKeyY"
        const sigMap = {};
        console.log("sigs:", data.validators_sig);
        if (data.validators_sig) {
            data.validators_sig.forEach(sig => {
                const key = `${sig.pub_key_x.toString()}_${sig.pub_key_y.toString()}`;
                sigMap[key] = sig;
            });
        }

        // 2. Iterate through the validators list (the ones in the Merkle Tree)
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            // Generate Merkle proof for this position
            const proof = data.tree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const v = data.validators[i];

            if (v) {
                // Construct the key to look up the signature
                const lookupKey = `${v.pub_key_x.toString()}_${v.pub_key_y.toString()}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked.toString());

                if (sig) {
                    // Match found: this validator signed
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    // No signature found for this pubkey
                    inputs.isSigned.push(0);
                    inputs.signaturesR8x.push("0");
                    inputs.signaturesR8y.push("0");
                    inputs.signaturesS.push("0");
                }
            } else {
                // Empty slot in the validator set
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.validatorStakes.push("0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("0");
                inputs.signaturesS.push("0");
            }
        }

        const fs = require('fs');
        const inputPath = path.join(__dirname, '../zk/validators/input.json');
        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready (Matched via PubKeys)");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

module.exports = {build_input};