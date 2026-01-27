module 0x0::groth16_check {
    use sui::groth16;
    
    // Try the exact VK from a known working Sui example
    // This VK is from a simple circuit that proves 1*1=1
    const KNOWN_VK: vector<u8> = x"2e97a90fac240628e80cdadafd5558fcd0721b6a5486212bd0e53013302edf27107385aa6f61f2b7b21a80dbc98e5603327970d2e455cc003565da777a35a68e6714d12bfae78a9d24fd5a8e63515dc0632935212e59a20b59b6290c15a5b0301800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed798e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2222b702f598f654d904d947fe9c990b6f9e888914f4d703569eb069d5c865aa6424b5ccfe6b2e3c21c3bcaf21e5d5a485746e5baaf84d481ceaa5cc67605fd540500000061d1e1f198d784ffca3a1729e8452db4fe213df35ac591443f2e9e4e5b30816a54a979e7c87ae69320db4145ded2e8fa9e8716694523a201bd2f88700e7cbe667b184c31eb02fa3052ed99cefb7ba4ae9ac459210b9fb30248748cae71ff1f566a2c71dc0a65211afc4886b394cc1aa07f418700595761a8c5695a938736159f708dc26f6fe2307d80172939b7cb3601d7b66776cf94b8ab89e55402aa52714d";
    
    public entry fun test_known_vk() {
        let curve = groth16::bn254();
        let pvk = groth16::prepare_verifying_key(&curve, &KNOWN_VK);
    }
    
    // Also test the other curve
    public entry fun test_bls12381() {
        let curve = groth16::bls12381();
        let pvk = groth16::prepare_verifying_key(&curve, &KNOWN_VK);
    }


public fun groth16_bn254_test() {
    let pvk = groth16::prepare_verifying_key(&groth16::bn254(), &x"94d781ec65145ed90beca1859d5f38ec4d1e30d4123424bb7b0c6fc618257b1551af0374b50e5da874ed3abbc80822e4378fdef9e72c423a66095361dacad8243d1a043fc217ea306d7c3dcab877be5f03502c824833fc4301ef8b712711c49ebd491d7424efffd121baf85244404bded1fe26bdf6ef5962a3361cef3ed1661d897d6654c60dca3d648ce82fa91dc737f35aa798fb52118bb20fd9ee1f84a7aabef505258940dc3bc9de41472e20634f311e5b6f7a17d82f2f2fcec06553f71e5cd295f9155e0f93cb7ed6f212d0ccddb01ebe7dd924c97a3f1fc9d03a9eb915020000000000000072548cb052d61ed254de62618c797853ad3b8a96c60141c2bfc12236638f1b0faf9ecf024817d8964c4b2fed6537bcd70600a85cdec0ca4b0435788dbffd81ab");
    // ...
}

}