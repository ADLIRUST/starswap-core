// Copyright (c) The Elements Studio Core Contributors
// SPDX-License-Identifier: Apache-2.0

address SwapAdmin {

module YieldFarming {
    use StarcoinFramework::Token;
    use StarcoinFramework::Signer;
    use StarcoinFramework::Timestamp;
    use StarcoinFramework::Errors;
    use StarcoinFramework::Math;
    use StarcoinFramework::U256;

    use SwapAdmin::BigExponential;

    const ERR_FARMING_INIT_REPEATE: u64 = 101;
    const ERR_FARMING_NOT_STILL_FREEZE: u64 = 102;
    const ERR_FARMING_STAKE_EXISTS: u64 = 103;
    const ERR_FARMING_STAKE_NOT_EXISTS: u64 = 104;
    const ERR_FARMING_HAVERST_NO_GAIN: u64 = 105;
    const ERR_FARMING_TOTAL_WEIGHT_IS_ZERO: u64 = 106;
    const ERR_FARMING_BALANCE_EXCEEDED: u64 = 108;
    const ERR_FARMING_NOT_ENOUGH_ASSET: u64 = 109;
    const ERR_FARMING_TIMESTAMP_INVALID: u64 = 110;
    const ERR_FARMING_TOKEN_SCALE_OVERFLOW: u64 = 111;
    const ERR_FARMING_CALC_LAST_IDX_BIGGER_THAN_NOW: u64 = 112;
    const ERR_FARMING_NOT_ALIVE: u64 = 113;
    const ERR_FARMING_ALIVE_STATE_INVALID: u64 = 114;

    /// The object of yield farming
    /// RewardTokenT meaning token of yield farming
    struct Farming<phantom PoolType, phantom RewardTokenT> has key, store {
        treasury_token: Token::Token<RewardTokenT>,
    }

    struct FarmingAsset<phantom PoolType, phantom AssetT> has key, store {
        asset_total_weight: u128,
        harvest_index: u128,
        last_update_timestamp: u64,
        // Release count per seconds
        release_per_second: u128,
        // Start time, by seconds, user can operate stake only after this timestamp
        start_time: u64,
        // Representing the pool is alive, false: not alive, true: alive.
        alive: bool,
    }

    /// To store user's asset token
    struct Stake<phantom PoolType, AssetT> has key, store {
        asset: AssetT,
        asset_weight: u128,
        last_harvest_index: u128,
        gain: u128,
    }

    /// Capability to modify parameter such as period and release amount
    struct ParameterModifyCapability<phantom PoolType, phantom AssetT> has key, store {}

    /// Harvest ability to harvest
    struct HarvestCapability<phantom PoolType, phantom AssetT> has key, store {}

    /// Called by token issuer
    /// this will declare a yield farming pool
    public fun initialize<
        PoolType: store,
        RewardTokenT: store>(account: &signer, treasury_token: Token::Token<RewardTokenT>) {
        let scaling_factor = Math::pow(10, BigExponential::exp_scale_limition());
        let token_scale = Token::scaling_factor<RewardTokenT>();
        assert!(token_scale <= scaling_factor, Errors::limit_exceeded(ERR_FARMING_TOKEN_SCALE_OVERFLOW));
        assert!(!exists_at<PoolType, RewardTokenT>(Signer::address_of(account)), Errors::invalid_state(ERR_FARMING_INIT_REPEATE));

        move_to(account, Farming<PoolType, RewardTokenT>{
            treasury_token,
        });
    }

    /// Add asset pools
    public fun add_asset<PoolType: store, AssetT: store>(
        account: &signer,
        release_per_second: u128,
        delay: u64): ParameterModifyCapability<PoolType, AssetT> {
        assert!(
            !exists_asset_at<PoolType, AssetT>(Signer::address_of(account)),
            Errors::invalid_state(ERR_FARMING_INIT_REPEATE)
        );

        let now_seconds = Timestamp::now_seconds();

        move_to(account, FarmingAsset<PoolType, AssetT>{
            asset_total_weight: 0,
            harvest_index: 0,
            last_update_timestamp: now_seconds,
            release_per_second,
            start_time: now_seconds + delay,
            alive: true
        });
        ParameterModifyCapability<PoolType, AssetT>{}
    }

    /// Remove asset for make this pool to the state of not alive
    /// Please make sure all user unstaking from this pool
    //    public fun remove_asset<PoolType: store, AssetT: store>(
    //        broker: address,
    //        cap: ParameterModifyCapability) acquires FarmingAsset {
    //        let ParameterModifyCapability {} = cap;
    //        let FarmingAsset<PoolType, AssetT> {
    //            asset_total_weight: _,
    //            harvest_index: _,
    //            last_update_timestamp: _,
    //            release_per_second: _,
    //            start_time: _,
    //            alive: _,
    //        } = move_from<FarmingAsset<PoolType, AssetT>>(broker);
    //    }

    public fun modify_parameter<PoolType: store, RewardTokenT: store, AssetT: store>(
        _cap: &ParameterModifyCapability<PoolType, AssetT>,
        broker: address,
        release_per_second: u128,
        alive: bool) acquires FarmingAsset {
        // Not support to shuttingdown alive state.
        assert!(alive, Errors::invalid_state(ERR_FARMING_ALIVE_STATE_INVALID));
        let farming_asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);
        // assert!(farming_asset.alive != alive, Errors::invalid_state(ERR_FARMING_ALIVE_STATE_INVALID));

        let now_seconds = Timestamp::now_seconds();
        farming_asset.last_update_timestamp = now_seconds;

        // if the pool is alive, then update index
        if (farming_asset.alive) {
            farming_asset.harvest_index = calculate_harvest_index_with_asset<PoolType, AssetT>(farming_asset, now_seconds);
        };

        farming_asset.release_per_second = release_per_second;
        farming_asset.alive = alive;
    }

    /// Call by stake user, staking amount of asset in order to get yield farming token
    public fun stake<PoolType: store, RewardTokenT: store, AssetT: store>(
        account: &signer,
        broker: address,
        asset: AssetT,
        asset_weight: u128,
        _cap: &ParameterModifyCapability<PoolType, AssetT>): HarvestCapability<PoolType, AssetT> acquires FarmingAsset {

        let account_address = Signer::address_of(account);
        assert!(!exists_stake_at_address<PoolType, AssetT>(account_address), Errors::invalid_state(ERR_FARMING_STAKE_EXISTS));

        let farming_asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);
        assert!(farming_asset.alive, Errors::invalid_state(ERR_FARMING_NOT_ALIVE));

        // Check locking time
        let now_seconds = Timestamp::now_seconds();
        assert!(farming_asset.start_time <= now_seconds, Errors::invalid_state(ERR_FARMING_NOT_STILL_FREEZE));

        let time_period = now_seconds - farming_asset.last_update_timestamp;

        if (farming_asset.asset_total_weight <= 0) {
            // Stake as first user
            let gain = farming_asset.release_per_second * (time_period as u128);
            move_to(account, Stake<PoolType, AssetT>{
                asset,
                asset_weight,
                last_harvest_index: 0,
                gain,
            });
            farming_asset.harvest_index = 0;
            farming_asset.asset_total_weight = asset_weight;
        } else {
            let new_harvest_index = calculate_harvest_index_with_asset<PoolType, AssetT>(farming_asset, now_seconds);
            move_to(account, Stake<PoolType, AssetT>{
                asset,
                asset_weight,
                last_harvest_index: new_harvest_index,
                gain: 0,
            });
            farming_asset.asset_total_weight = farming_asset.asset_total_weight + asset_weight;
            farming_asset.harvest_index = new_harvest_index;
        };
        farming_asset.last_update_timestamp = now_seconds;
        HarvestCapability<PoolType, AssetT>{}
    }

    /// Unstake asset from farming pool
    public fun unstake<PoolType: store, RewardTokenT: store, AssetT: store>(
        account: &signer,
        broker: address,
        cap: HarvestCapability<PoolType, AssetT>)
    : (AssetT, Token::Token<RewardTokenT>) acquires Farming, FarmingAsset, Stake {
        // Destroy capability
        let HarvestCapability<PoolType, AssetT>{} = cap;

        let farming = borrow_global_mut<Farming<PoolType, RewardTokenT>>(broker);
        let farming_asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);

        let Stake<PoolType, AssetT>{ last_harvest_index, asset_weight, asset, gain } =
            move_from<Stake<PoolType, AssetT>>(Signer::address_of(account));

        let now_seconds = Timestamp::now_seconds();
        let new_harvest_index = calculate_harvest_index_with_asset<PoolType, AssetT>(farming_asset, now_seconds);

        let period_gain = calculate_withdraw_amount(new_harvest_index, last_harvest_index, asset_weight);
        let total_gain = gain + period_gain;
        let withdraw_token = Token::withdraw<RewardTokenT>(&mut farming.treasury_token, total_gain);

        // Dont update harvest index that because the `Stake` object has droped.
        // let new_index = calculate_harvest_index_with_asset<PoolType, AssetT>(farming_asset, now_seconds);
        assert!(farming_asset.asset_total_weight >= asset_weight, Errors::invalid_state(ERR_FARMING_NOT_ENOUGH_ASSET));

        // Update farm asset
        farming_asset.asset_total_weight = farming_asset.asset_total_weight - asset_weight;
        farming_asset.last_update_timestamp = now_seconds;

        if (farming_asset.alive) {
            farming_asset.harvest_index = new_harvest_index;
        };

        (asset, withdraw_token)
    }

    /// Harvest yield farming token from stake
    public fun harvest<PoolType: store,
                       RewardTokenT: store,
                       AssetT: store>(
        account: address,
        broker: address,
        amount: u128,
        _cap: &HarvestCapability<PoolType, AssetT>): Token::Token<RewardTokenT> acquires Farming, FarmingAsset, Stake {
        let farming = borrow_global_mut<Farming<PoolType, RewardTokenT>>(broker);
        let farming_asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);
        let stake = borrow_global_mut<Stake<PoolType, AssetT>>(account);

        let now_seconds = Timestamp::now_seconds();
        let new_harvest_index = calculate_harvest_index_with_asset<PoolType, AssetT>(farming_asset, now_seconds);

        let period_gain = calculate_withdraw_amount(
            new_harvest_index,
            stake.last_harvest_index,
            stake.asset_weight
        );

        let total_gain = stake.gain + period_gain;
        //assert!(total_gain > 0, Errors::limit_exceeded(ERR_FARMING_HAVERST_NO_GAIN));
        assert!(total_gain >= amount, Errors::limit_exceeded(ERR_FARMING_BALANCE_EXCEEDED));

        let withdraw_amount = if (amount <= 0) {
            total_gain
        } else {
            amount
        };

        let withdraw_token = Token::withdraw<RewardTokenT>(&mut farming.treasury_token, withdraw_amount);
        stake.gain = total_gain - withdraw_amount;
        stake.last_harvest_index = new_harvest_index;

        if (farming_asset.alive) {
            farming_asset.harvest_index = new_harvest_index;
        };
        farming_asset.last_update_timestamp = now_seconds;

        withdraw_token
    }

    /// The user can quering all yield farming amount in any time and scene
    public fun query_gov_token_amount<PoolType: store,
                                      RewardTokenT: store,
                                      AssetT: store>(account: address, broker: address): u128 acquires FarmingAsset, Stake {
        let farming_asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);
        let stake = borrow_global_mut<Stake<PoolType, AssetT>>(account);
        let now_seconds = Timestamp::now_seconds();

        let new_harvest_index = calculate_harvest_index_with_asset<PoolType, AssetT>(
            farming_asset,
            now_seconds
        );

        let new_gain = calculate_withdraw_amount(
            new_harvest_index,
            stake.last_harvest_index,
            stake.asset_weight
        );

        stake.gain + new_gain
    }

    /// Query total stake count from yield farming resource
    public fun query_total_stake<PoolType: store,
                                 AssetT: store>(broker: address): u128 acquires FarmingAsset {
        let farming_asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);
        farming_asset.asset_total_weight
    }

    /// Query stake weight from user staking objects.
    public fun query_stake<PoolType: store,
                           AssetT: store>(account: address): u128 acquires Stake {
        let stake = borrow_global_mut<Stake<PoolType, AssetT>>(account);
        stake.asset_weight
    }

    /// Queyry pool info from pool type
    /// return value: (alive, release_per_second, asset_total_weight, harvest_index)
    public fun query_info<PoolType: store, AssetT: store>(broker: address): (bool, u128, u128, u128) acquires FarmingAsset {
        let asset = borrow_global_mut<FarmingAsset<PoolType, AssetT>>(broker);
        (
            asset.alive,
            asset.release_per_second,
            asset.asset_total_weight,
            asset.harvest_index
        )
    }

    /// Update farming asset
    fun calculate_harvest_index_with_asset<PoolType, AssetT>(farming_asset: &FarmingAsset<PoolType, AssetT>, now_seconds: u64): u128 {
        // Recalculate harvest index
        if (farming_asset.asset_total_weight <= 0) {
            calculate_harvest_index_weight_zero(
                farming_asset.harvest_index,
                farming_asset.last_update_timestamp,
                now_seconds,
                farming_asset.release_per_second
            )
        } else {
            calculate_harvest_index(
                farming_asset.harvest_index,
                farming_asset.asset_total_weight,
                farming_asset.last_update_timestamp,
                now_seconds,
                farming_asset.release_per_second
            )
        }
    }

    /// There is calculating from harvest index and global parameters without asset_total_weight
    public fun calculate_harvest_index_weight_zero(harvest_index: u128,
                                                   last_update_timestamp: u64,
                                                   now_seconds: u64,
                                                   release_per_second: u128): u128 {
        assert!(last_update_timestamp <= now_seconds, Errors::invalid_argument(ERR_FARMING_TIMESTAMP_INVALID));
        let time_period = now_seconds - last_update_timestamp;
        let addtion_index = release_per_second * (time_period as u128);
        let index_u256 = U256::add(
            U256::from_u128(harvest_index),
            BigExponential::mantissa(BigExponential::exp_direct_expand(addtion_index))
        );
        BigExponential::to_safe_u128(index_u256)
    }

    /// There is calculating from harvest index and global parameters
    public fun calculate_harvest_index(harvest_index: u128,
                                       asset_total_weight: u128,
                                       last_update_timestamp: u64,
                                       now_seconds: u64,
                                       release_per_second: u128): u128 {
        assert!(asset_total_weight > 0, Errors::invalid_argument(ERR_FARMING_TOTAL_WEIGHT_IS_ZERO));
        assert!(last_update_timestamp <= now_seconds, Errors::invalid_argument(ERR_FARMING_TIMESTAMP_INVALID));

        let time_period = now_seconds - last_update_timestamp;
        let numr = release_per_second * (time_period as u128);
        let denom = asset_total_weight;
        let index_u256 = U256::add(
            U256::from_u128(harvest_index),
            BigExponential::mantissa(BigExponential::exp(numr, denom))
        );
        BigExponential::to_safe_u128(index_u256)
    }

    /// This function will return a gain index
    public fun calculate_withdraw_amount(harvest_index: u128,
                                         last_harvest_index: u128,
                                         asset_weight: u128): u128 {
        assert!(harvest_index >= last_harvest_index, Errors::invalid_argument(ERR_FARMING_CALC_LAST_IDX_BIGGER_THAN_NOW));
        let amount_u256 = U256::mul(U256::from_u128(asset_weight), U256::from_u128(harvest_index - last_harvest_index));
        BigExponential::truncate(BigExponential::exp_from_u256(amount_u256))
    }

    /// Check the Farming of TokenT is exists.
    public fun exists_at<PoolType: store, RewardTokenT: store>(broker: address): bool {
        exists<Farming<PoolType, RewardTokenT>>(broker)
    }

    /// Check the Farming of AsssetT is exists.
    public fun exists_asset_at<PoolType: store, AssetT: store>(broker: address): bool {
        exists<FarmingAsset<PoolType, AssetT>>(broker)
    }

    /// Check stake at address exists.
    public fun exists_stake_at_address<PoolType: store, AssetT: store>(account: address): bool {
        exists<Stake<PoolType, AssetT>>(account)
    }
}
}