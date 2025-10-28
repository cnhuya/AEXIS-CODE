module dev::QiaraTiersV12{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use dev::QiaraMathV9::{Self as QiaraMath};
    use dev::QiaraStorageV25::{Self as storage};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_TIER_NOT_FOUND: u64 = 2;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

/// === STRUCTS ===
    
    struct Tier has store, key, drop {
        tierID: u8,
        tierName: String,
        efficiency: u64,
        multiplier: u64,
    }


/// === INIT ===
    fun init_module(admin: &signer){

    }

/// === HELPER FUNCTIONS ===
  
    fun build_tiers(): vector<Tier>{
        
        let tier0 = Tier {
            tierID: 0,
            tierName: convert_tier_to_string(0),
            efficiency: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T0_EFF"))),
            multiplier: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T0_X"))),
        };

        let tier1 = Tier {
            tierID: 1,
            tierName: convert_tier_to_string(1),
            efficiency: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T1_EFF"))),
            multiplier: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T1_X"))),
        };

        let tier2 = Tier {
            tierID: 2,
            tierName: convert_tier_to_string(2),
            efficiency: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T2_EFF"))),
            multiplier: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T2_X"))),
        };

        let tier3 = Tier {
            tierID: 3,
            tierName: convert_tier_to_string(3),
            efficiency: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T3_EFF"))),
            multiplier: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T3_X"))),
        };

        let tier4 = Tier {
            tierID: 4,
            tierName: convert_tier_to_string(4),
            efficiency: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T4_EFF"))),
            multiplier: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T4_X"))),
        };
        
        let tier5 = Tier {
            tierID: 5,
            tierName: convert_tier_to_string(5),
            efficiency: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T5_EFF"))),
            multiplier: storage::expect_u64(storage::viewConstant(utf8(b"QiaraTiers"), utf8(b"T5_X"))),
        };

        return vector[tier0, tier1, tier2, tier3, tier4, tier5]
    }  
  
    fun view_tier(id: u8): Tier{
        let tiers = build_tiers();
        let len = vector::length(&tiers);

        while (len > 0){
            let tier = vector::pop_back(&mut tiers);
            if (tier.tierID == id){
                return tier;
            };
        };

        abort(ERROR_TIER_NOT_FOUND)
    }  

/// === VIEW FUNCTIONS ===
    #[view]
    public fun all_tiers():vector<Tier>{
        build_tiers()
    }

    #[view]
    public fun get_tier(id:u8):Tier{
        view_tier(id)
    }

  // === GET TIER DATA  === //
        #[view]
        public fun tier_efficiency(id: u8): u64{
            let tier = get_tier(id);
            tier.efficiency
        }

        #[view]
        public fun tier_multiplier(id: u8): u64{
            let tier = get_tier(id);
            tier.multiplier
        }

        #[view]
        public fun lend_ratio(id: u8): u64 {
            let tier = get_tier(id);
            tier.efficiency
        }

        #[view]
        public fun minimal_w_fee(id: u8): u64 {
            let tier = get_tier(id);
            (tier.multiplier * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"W_FEE"))))
        }

        #[view]
        public fun w_limit(id: u8): u64 {
            let tier = get_tier(id);
            (tier.multiplier * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"W_CAP"))))
        }

        #[view]
        public fun rate_scale(id: u8, isLending: bool): u16 {
            let x = 200;
            if(isLending) { x = 0 };
            ((storage::expect_u16(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - ((id as u16)*100)) - x)
        }

        #[view]
        public fun deposit_limit(id: u8): u128 {
            let tier = get_tier(id);
            (tier.efficiency * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"DEPOSIT_LIMIT"))) as u128)
        }

        #[view]
        public fun borrow_limit(id: u8): u128 {
            let tier = get_tier(id);
            (tier.efficiency * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"BORROW_LIMIT"))) as u128)
        }


        #[view]
        public fun profit_fee(id: u8): u64 {
            let tier = get_tier(id);
            (tier.efficiency * storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"PROFIT_FEE"))))
        }

        #[view]
        public fun leverage_cut(id: u8): u64 {
            let tier = get_tier(id);
            (tier.efficiency * storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"LEVERAGE_CUT"))))
        }

        #[view]
        public fun max_position(id: u8): u128{
            let tier = get_tier(id);
            (tier.efficiency * storage::expect_u64(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"MAX_POSITION"))) as u128)
        }

        #[view]
        public fun perps_rate_scale(id: u8): u16 {
            storage::expect_u16(storage::viewConstant(utf8(b"QiaraPerps"), utf8(b"PERPS_PERCENTAGE_SCALE"))) - ((id as u16)*1000)
        }



// === CONVERT === //
    public fun convert_tier_to_string(tier: u8): String{
        if(tier == 0 ){
            return utf8(b"Stable")
        } else if(tier == 1 ){
            return utf8(b"Bluechip")
        } else if(tier == 2 ){
            return utf8(b"Adopted")
        } else if(tier == 3 ){
            return utf8(b"Volatile")
        } else if(tier == 4){
            return utf8(b"Experimental")
        } else if(tier == 5){
            return utf8(b"Fragile")
        } else{
            return utf8(b"Unknown")
        }
    }
}
