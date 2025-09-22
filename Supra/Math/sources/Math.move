module dev::QiaraMath {

    fun pow10_u256(n: u8): u256 {
        let i = 0u8;
        let p = 1u256;
        while (i < n) {
            p = p * 10;
            i = i + 1;
        };
        p
    }
}
