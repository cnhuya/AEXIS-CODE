module dev::QiaraMath {

    public fun pow10_u256(n: u8): u256 {
        let i = 0u8;
        let p = 1u256;
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
        let i: u256 = 1;

        // Compute e^x  1 + x + x^2/2! + x^3/3! + ...
        while (i < 20) { // 20 terms for decent accuracy
            term = (term * x) / (i * scale);
            result = result + term;
            i = i + 1;
        };

        result
    }

    #[view]
    public fun compute_rate(rate: u256, utilization: u256, exp_scale: u256, decimals: u8): u256 {
        let scale = pow10_u256(decimals);

        // Step 1: compute utilization / scale
        let ratio = (utilization * scale) / exp_scale;

        // Step 2: first exponential
        let first_exp = exp(ratio, decimals);

        // Step 3: second exponential
        let second_exp = exp(first_exp, decimals);

        // Step 4: subtract e^1 (scaled)
        let e1 = exp(scale, decimals); // e^1
        let adjusted = second_exp - e1;

        // Step 5: third exponential
        let third_exp = exp(adjusted, decimals);

        // Step 6: multiply by rate
        (rate * third_exp)
    }


}
