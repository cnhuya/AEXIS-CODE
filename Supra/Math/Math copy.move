module dev::QiaraMath {

public fun pow10_u256(n: u8): u256 {
    let p = 1;
    let i = 0;
    while (i < n) {
        p = p * 10;
        i = i + 1;
    };
    p
}

#[view]
public fun exp(x: u256, decimals: u8): u256 {
    let scale = pow10_u256(decimals);
    let result = scale; // term 0 = 1.0
    let term = scale;   // running term
    let i  = 1;

    while (i < 40) { // increase terms for better accuracy
        // Correct fixed-point formula: term = term * x / (scale * i)
        term = (term * x) / (scale * i);
        result = result + term;
        i = i + 1;
    };

    result
}

// supra move tool view --function-id 0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraMath::compute_rate --args u256:3000 u256:1000000000 u256:28000000 u8:3
// vaults borroing lending calculations
      #[view]
    public fun compute_rate(
        rate: u256,
        utilization: u256,
        exp_scale: u256,
        decimals: u8
    ): u256 {
        let scale = pow10_u256(decimals);
        let exp_decimals: u8 = 8; // fixed internal precision for exp()
        let exp_scale_factor = pow10_u256(exp_decimals);

        // x = utilization / exp_scale, but we must preserve precision for exp()
        // So compute: x_scaled = (utilization * exp_scale_factor) / exp_scale
        let x_scaled = (utilization * exp_scale_factor) / exp_scale;

        // Compute e^x in fixed point with exp_decimals precision
        let exp_x = exp(x_scaled, exp_decimals);

        // (exp(x) - 1) / (exp_scale/2)
        let numerator = exp_x - exp_scale_factor; // subtract 1.0
        let denominator = exp_scale / 2;

        // factor is scaled by exp_decimals
        let factor = (numerator * 100) / denominator;

        // rate + rate * factor/scale
        let rate_increase = (rate * factor) / exp_scale_factor;
        let final_rate = rate + rate_increase;

        // Adjust to requested output decimals
        (final_rate * scale) / 100
    }









//supra move tool view --function-id 0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraMath::compute_rate_3 
//--args u256:248 u256:1000000000 u256:499990300 u256:5 u8:3


////supra move tool view --function-id 0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraMath::compute_rate_3 --args u256:248 u256:1000000000 u256:499990300 u256:5 u8:3
#[view]
public fun compute_rate_3(
    global_fee: u256,
    utilization: u256,
    exp_scale: u256,
    leverage: u256,
    decimals: u8
): u256 {
    let scale = pow10_u256(decimals);

    // FIX: higher precision ratio
    let ratio = (utilization * scale * scale) / exp_scale;

    // compute exp with double-precision scaling
    let exp_part = exp(ratio, decimals * 2);
    let exp_part = exp_part / scale;

    // leverage multiplier = 1 + leverage/100, scaled
    let leverage_multiplier = scale + ((leverage * scale) / 100);

    // result = global_fee * exp(ratio) * (1 + leverage/100)
    let result = (global_fee * exp_part) / scale;
    let result = (result * leverage_multiplier) / scale;

    result
}



//supra move tool view --function-id 0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraMath::compute_rate_2 
//--args u256:1000000 u256:50 u256:97 u8:7
#[view]
public fun compute_rate_2(
    leverage: u256,
    exp_scale: u256,
    exp_aggression: u256,
    decimals: u8
): u256 {
    let scale = pow10_u256(decimals);

    // leverage / (exp_scale / exp_aggression)
    let denominator = (exp_scale * scale) / exp_aggression; // scaled
    let fraction = (leverage * scale) / denominator;        // scaled fraction

    // result = exp_scale - (exp_scale * fraction / scale)
    // multiply exp_scale by scale so result is also scaled
    let result = (exp_scale * scale) - ((exp_scale * fraction));

    result
}



}
