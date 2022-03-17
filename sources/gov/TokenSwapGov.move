// Copyright (c) The Elements Studio Core Contributors
// SPDX-License-Identifier: Apache-2.0

address SwapAdmin {
module TokenSwapGov {
    use StarcoinFramework::Token;
    use StarcoinFramework::Account;
    use StarcoinFramework::Math;
    use StarcoinFramework::Signer;
    use StarcoinFramework::Timestamp;
    use StarcoinFramework::Errors;

    use SwapAdmin::STAR;
    use SwapAdmin::TokenSwapFarm;
    use SwapAdmin::TokenSwapSyrup;
    use SwapAdmin::TokenSwapConfig;
    use SwapAdmin::TokenSwapGovPoolType::{
        PoolTypeInitialLiquidity,
        PoolTypeCommunity,
        PoolTypeDaoTreasury,
        PoolTypeFarmPool ,
        PoolTypeSyrup ,
        PoolTypeTeam,
    };

    //

    const GENESIS_TIMESTAMP:u64 = 0;

    // 1 year =  1 * 365 * 86400

    // farm 2 year
    const GOV_PERCENT_FARM_LOCK_TIME : u64= 2 * 365 * 86400;

    // syrup 1 year
    const GOV_PERCENT_SYRUP_LOCK_TIME : u64 = 1 * 365 * 86400;

    // community 2 year
    const GOV_PERCENT_COMMUNITY_LOCK_TIME : u64 = 2 * 365 * 86400;

    //team 2 year
    const GOV_PERCENT_TEAM_LOCK_TIME : u64 = 2 * 365 * 86400;




    // 1e8
    const GOV_TOTAL: u128 = 100000000;

    // 10%
    const GOV_PERCENT_TEAM: u64 = 10;
    // 5%
    const GOV_PERCENT_COMMUNITY: u64 = 5;
    // 60%
    const GOV_PERCENT_FARM: u64 = 60;
    // 10%
    const GOV_PERCENT_SYRUP: u64 = 10;
    // 1%
    const GOV_PERCENT_INITIAL_LIQUIDITY: u64 = 1;
    // 14%
    const GOV_PERCENT_DAO_TREASURY: u64 = 14;


    // 5%
    const GOV_PERCENT_FARM_GENESIS: u64 = 5;
    // 5%
    const GOV_PERCENT_SYRUP_GENESIS: u64 = 5;
    // 2%
    const GOV_PERCENT_COMMUNITY_GENESIS: u64 = 2;
    // 2%
    const GOV_PERCENT_DAO_TREASURY_GENESIS: u64 = 2;


    const ERR_DEPRECATED_UPGRADE_ERROR: u64 = 201;
    const ERR_WITHDRAW_AMOUNT_TOO_MANY: u64 = 202;


    #[test] public fun test_all_issued_amount() {
        let total = GOV_PERCENT_TEAM +
                    GOV_PERCENT_COMMUNITY +
                    GOV_PERCENT_FARM +
                    GOV_PERCENT_SYRUP +
                    GOV_PERCENT_INITIAL_LIQUIDITY +
                    GOV_PERCENT_DAO_TREASURY;

        assert!(total == 100, 1001);

        assert!(calculate_amount_from_percent(GOV_PERCENT_TEAM) == 10000000, 1002);
        assert!(calculate_amount_from_percent(GOV_PERCENT_COMMUNITY) == 5000000, 1002);
        assert!(calculate_amount_from_percent(GOV_PERCENT_FARM) == 40000000, 1002);
        assert!(calculate_amount_from_percent(GOV_PERCENT_SYRUP) == 20000000, 1003);
        assert!(calculate_amount_from_percent(GOV_PERCENT_INITIAL_LIQUIDITY) == 1000000, 1004);
        assert!(calculate_amount_from_percent(GOV_PERCENT_DAO_TREASURY) == 24000000, 1005);
    }


    struct GovCapability has key, store {
        mint_cap: Token::MintCapability<STAR::STAR>,
        burn_cap: Token::BurnCapability<STAR::STAR>,
    }

    struct GovTreasury<phantom PoolType> has key, store {
        treasury: Token::Token<STAR::STAR>,
        locked_start_timestamp: u64,    // locked start time
        locked_total_timestamp: u64,    // locked total time
    }

    /// Initial as genesis that will create pool list by Starswap Ecnomic Model list
    public fun genesis_initialize(account: &signer) {
        STAR::assert_genesis_address(account);
        STAR::init(account);

        let precision = STAR::precision();
        let scaling_factor = Math::pow(10, (precision as u64));
        let now_timestamp = Timestamp::now_seconds();

        // Release 40% for farm. genesis release 5%.
        let farm_genesis = calculate_amount_from_percent(GOV_PERCENT_FARM_GENESIS) * (scaling_factor as u128);
        STAR::mint(account, farm_genesis);
        let farm_genesis_token = Account::withdraw<STAR::STAR>(account, farm_genesis);
        TokenSwapFarm::initialize_farm_pool(account, farm_genesis_token);


        // Release 20% for syrup token stake. genesis release 5%.
        let syrup_genesis = calculate_amount_from_percent(GOV_PERCENT_SYRUP_GENESIS) * (scaling_factor as u128);
        STAR::mint(account, syrup_genesis);
        let syrup_genesis_token = Account::withdraw<STAR::STAR>(account, syrup_genesis);
        TokenSwapSyrup::initialize(account, syrup_genesis_token);


        //Release 5% for community. genesis release 2%.
        let community_total = calculate_amount_from_percent(GOV_PERCENT_COMMUNITY_GENESIS) * (scaling_factor as u128);
        STAR::mint(account, community_total);
        
        move_to(account, GovTreasury<PoolTypeCommunity>{
            treasury: Account::withdraw<STAR::STAR>(account, community_total),
            locked_start_timestamp : now_timestamp,
            locked_total_timestamp : 0,
        });
        

        //  Release 1% for initial liquidity
        let initial_liquidity_total = calculate_amount_from_percent(GOV_PERCENT_INITIAL_LIQUIDITY) * (scaling_factor as u128);
        STAR::mint(account, initial_liquidity_total);
        move_to(account, GovTreasury<PoolTypeInitialLiquidity>{
            treasury: Account::withdraw<STAR::STAR>(account, initial_liquidity_total),
            locked_start_timestamp : now_timestamp,
            locked_total_timestamp : 0,
        });
    }

    public fun linear_initialize(account: &signer) acquires GovTreasury{
        STAR::assert_genesis_address(account);

        let precision = STAR::precision();
        let scaling_factor = Math::pow(10, (precision as u64));
        let genesis_timestamp  = 0;

        // linear 60% - 5 % for farm. 
        let farm_linear = calculate_amount_from_percent(GOV_PERCENT_FARM - GOV_PERCENT_FARM_GENESIS ) * (scaling_factor as u128);
        STAR::mint(account, farm_linear);
        move_to(account, GovTreasury<PoolTypeFarmPool>{
            treasury: Account::withdraw<STAR::STAR>(account, farm_linear),
            locked_start_timestamp : genesis_timestamp,
            locked_total_timestamp : GOV_PERCENT_FARM_LOCK_TIME,
        });

        // linear 10% - 5 % for syrup. 
        let syrup_linear = calculate_amount_from_percent(GOV_PERCENT_SYRUP - GOV_PERCENT_SYRUP_GENESIS ) * (scaling_factor as u128);
        STAR::mint(account, syrup_linear);
        move_to(account, GovTreasury<PoolTypeSyrup>{
            treasury: Account::withdraw<STAR::STAR>(account, syrup_linear),
            locked_start_timestamp : genesis_timestamp,
            locked_total_timestamp : GOV_PERCENT_SYRUP_LOCK_TIME,
        });



        // linear 5% - 2 % for community. 
        let community_linear = calculate_amount_from_percent(GOV_PERCENT_COMMUNITY - GOV_PERCENT_COMMUNITY_GENESIS ) * (scaling_factor as u128);
        STAR::mint(account, community_linear);
        let community_linear_token = Account::withdraw<STAR::STAR>(account, community_linear);
        let treasury = borrow_global_mut<GovTreasury<PoolTypeCommunity>>(Signer::address_of(account));
        Token::deposit(&mut treasury.treasury,community_linear_token) ;
        treasury.locked_start_timestamp = genesis_timestamp;
        treasury.locked_total_timestamp = GOV_PERCENT_COMMUNITY_LOCK_TIME;



        // linear 10%  for team. 
        let team_linear = calculate_amount_from_percent(GOV_PERCENT_TEAM ) * (scaling_factor as u128);
        STAR::mint(account, team_linear);
        move_to(account, GovTreasury<PoolTypeTeam>{
            treasury: Account::withdraw<STAR::STAR>(account, team_linear),
            locked_start_timestamp : genesis_timestamp,
            locked_total_timestamp : GOV_PERCENT_TEAM_LOCK_TIME,
        });
    }

    public fun  linear_withdraw_farm (account: &signer ,to:address,amount :u128)acquires GovTreasury{
        
        TokenSwapConfig::assert_global_freeze();

        let now_timestamp = Timestamp::now_seconds();
        let precision = STAR::precision();
        let scaling_factor = Math::pow(10, (precision as u64));

        let treasury = borrow_global_mut<GovTreasury<PoolTypeFarmPool>>(Signer::address_of(account));

        let elapsed_time = now_timestamp - treasury.locked_start_timestamp;

        let can_withdraw_amount = if (elapsed_time >= treasury.locked_total_timestamp) {
            Token::value<STAR::STAR>(&treasury.treasury)
        }else {
            let second_release =   calculate_amount_from_percent(GOV_PERCENT_FARM - GOV_PERCENT_FARM_GENESIS ) * (scaling_factor as u128) / (treasury.locked_total_timestamp as u128);
            (( treasury.locked_start_timestamp - GENESIS_TIMESTAMP  ) as u128) * second_release
        };
        assert!(can_withdraw_amount >= amount, Errors::invalid_argument(ERR_WITHDRAW_AMOUNT_TOO_MANY));

        let disp_token = Token::withdraw<STAR::STAR>(&mut treasury.treasury, amount);
        Account::deposit<STAR::STAR>(to, disp_token);
        
    }

    /// dispatch to acceptor from governance treasury pool
    public fun dispatch<PoolType: store>(account: &signer, acceptor: address, amount: u128) acquires GovTreasury {
        TokenSwapConfig::assert_global_freeze();

        let now_timestamp = Timestamp::now_seconds();
        let treasury = borrow_global_mut<GovTreasury<PoolType>>(Signer::address_of(account));
        if((treasury.locked_start_timestamp + treasury.locked_total_timestamp) <= now_timestamp ) {
            let disp_token = Token::withdraw<STAR::STAR>(&mut treasury.treasury, amount);
            Account::deposit<STAR::STAR>(acceptor, disp_token);
        }
    }

    /// Get balance of treasury
    public fun get_balance_of_treasury<PoolType: store>(): u128 acquires GovTreasury {
        let treasury = borrow_global_mut<GovTreasury<PoolType>>(STAR::token_address());
        Token::value<STAR::STAR>(&treasury.treasury)
    }


    fun calculate_amount_from_percent(percent: u64): u128 {
        let per: u128 = 100;
        ((GOV_TOTAL / per)) * (percent as u128)
    }

    /// Upgrade v2 to v3, only called in barnard net for compatibility
    /// TODO(9191stc): to be remove it before deploy to main net
    public(script) fun upgrade_v2_to_v3_for_syrup_on_testnet(_signer: signer, _amount: u128)  {
        abort Errors::deprecated(ERR_DEPRECATED_UPGRADE_ERROR)
    }

    /// only called in barnard net for compatibility
    public(script) fun upgrade_dao_treasury_genesis(signer: signer) {
        STAR::assert_genesis_address(&signer);
        //upgrade dao treasury genesis can only be execute once
        if(! exists<GovTreasury<PoolTypeDaoTreasury>>(Signer::address_of(&signer))){
            let precision = STAR::precision();
            let scaling_factor = Math::pow(10, (precision as u64));
            let now_timestamp = Timestamp::now_seconds();

            //  Release 24% for dao treasury. genesis release 2%.
            let dao_treasury_genesis = calculate_amount_from_percent(GOV_PERCENT_DAO_TREASURY_GENESIS) * (scaling_factor as u128);
            STAR::mint(&signer, dao_treasury_genesis);
            move_to(&signer, GovTreasury<PoolTypeDaoTreasury>{
                treasury: Account::withdraw<STAR::STAR>(&signer, dao_treasury_genesis),
                locked_start_timestamp : now_timestamp,
                locked_total_timestamp : 0,
            });
        };
    }
}
}