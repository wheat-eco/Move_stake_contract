module devnet_staking::staking_protocol {
    use std::u64;
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::event;
    use devnet_staking::mock_swhit::MOCK_SWHIT;

    /* ========== ERRORS ========== */

    const ERewardDurationNotExpired: u64 = 100;
    const EZeroRewardRate: u64 = 101;
    const EZeroAmount: u64 = 102;
    const ELowRewardsTreasuryBalance: u64 = 103;
    const ERequestedAmountExceedsStaked: u64 = 104;
    const ENoRewardsToClaim: u64 = 105;
    const ENoStakedTokens: u64 = 106;
    const ENoPriorTokenStake: u64 = 107;

    /* ========== OBJECTS ========== */

    /// Reward state tracking
    public struct RewardState has key, store {
        id: UID,
        duration: u64,
        finish_at: u64,
        updated_at: u64,
        reward_rate: u64,
    }

    /// User state tracking
    public struct UserState has key, store {
        id: UID,
        reward_per_token_stored: u64,
        user_reward_per_token_paid: VecMap<address, u64>,
        balance_of: VecMap<address, u64>,
        rewards: VecMap<address, u64>,
    }

    /// Treasury holding staked and reward tokens
    public struct Treasury has key, store {
        id: UID,
        rewards_treasury: Balance<MOCK_SWHIT>,
        staked_coins_treasury: Balance<SUI>,
    }

    /// Admin capability
    public struct AdminCap has key, store {
        id: UID
    }

    /* ========== EVENTS ========== */

    /// Event emitted when rewards are added
    public struct RewardAdded has copy, drop, store {
        reward: u64
    }

    /// Event emitted when reward duration is updated
    public struct RewardDurationUpdated has copy, drop, store {
         new_duration: u64
    }

    /// Event emitted when tokens are staked
    public struct Staked has copy, drop, store {
        user: address,
        amount: u64
    }

    /// Event emitted when tokens are withdrawn
    public struct Withdrawn has copy, drop, store {
        user: address,
        amount: u64
    }

    /// Event emitted when rewards are paid
    public struct RewardPaid has copy, drop, store {
        user: address,
        reward: u64
    }

    /* ========== CONSTRUCTOR ========== */

    fun init(ctx: &mut TxContext) {
transfer::share_object(RewardState {
id: object::new(ctx),
duration: 0,
finish_at: 0,
updated_at: 0,
reward_rate: 0
});

transfer::share_object(UserState {
id: object::new(ctx),
reward_per_token_stored: 0,
user_reward_per_token_paid: vec_map::empty(),
balance_of: vec_map::empty(),
rewards: vec_map::empty()
});

transfer::share_object(Treasury {
id: object::new(ctx),
rewards_treasury: balance::zero(),
staked_coins_treasury: balance::zero(),
});

transfer::transfer(AdminCap {
id: object::new(ctx)
}, tx_context::sender(ctx));
}
    /* ========== USER FUNCTIONS ========== */

    public entry fun stake(
        payment: Coin<SUI>, 
        user_state: &mut UserState, 
        reward_state: &mut RewardState, 
        treasury: &mut Treasury, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let account = tx_context::sender(ctx);
        let total_staked_supply = balance::value(&treasury.staked_coins_treasury);
        let amount = coin::value(&payment);

        if (!vec_map::contains(&user_state.balance_of, &account)) {
            vec_map::insert(&mut user_state.balance_of, account, 0);
            vec_map::insert(&mut user_state.user_reward_per_token_paid, account, 0);
            vec_map::insert(&mut user_state.rewards, account, 0);
        };

        update_reward(total_staked_supply, account, user_state, reward_state, clock);

        let balance = coin::into_balance(payment);
        balance::join(&mut treasury.staked_coins_treasury, balance);

        let balance_of_account = vec_map::get_mut(&mut user_state.balance_of, &account);
        *balance_of_account = *balance_of_account + amount;

        event::emit(Staked { user: account, amount });
    }

    public entry fun withdraw(
        user_state: &mut UserState, 
        reward_state: &mut RewardState, 
        treasury: &mut Treasury, 
        amount: u64, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let account = tx_context::sender(ctx);
        let balance_of_account_imut = vec_map::get(&user_state.balance_of, &account);
        let total_staked_supply = balance::value(&treasury.staked_coins_treasury);

        assert!(vec_map::contains(&user_state.balance_of, &account), ENoStakedTokens);
        assert!(amount > 0, EZeroAmount);
        assert!(amount <= *balance_of_account_imut, ERequestedAmountExceedsStaked);
        
        update_reward(total_staked_supply, account, user_state, reward_state, clock);

        let balance_of_account = vec_map::get_mut(&mut user_state.balance_of, &account);
        *balance_of_account = *balance_of_account - amount;

        let withdrawal_amount = coin::take(&mut treasury.staked_coins_treasury, amount, ctx);
        transfer::public_transfer(withdrawal_amount, account);

        event::emit(Withdrawn { user: account, amount });
    }

    public entry fun get_reward(
        user_state: &mut UserState, 
        reward_state: &mut RewardState, 
        treasury: &mut Treasury, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let account = tx_context::sender(ctx);
        let total_staked_supply = balance::value(&treasury.staked_coins_treasury);

        assert!(vec_map::contains(&user_state.rewards, &account), ENoPriorTokenStake);
        let rewards_account_imut = vec_map::get(&user_state.rewards, &account);
        assert!(*rewards_account_imut > 0, ENoRewardsToClaim);

        update_reward(total_staked_supply, account, user_state, reward_state, clock);

        let rewards_account = vec_map::get_mut(&mut user_state.rewards, &account);
        let staking_rewards = coin::take(&mut treasury.rewards_treasury, *rewards_account, ctx);
        
        event::emit(RewardPaid { user: account, reward: *rewards_account });

        *rewards_account = 0;
        transfer::public_transfer(staking_rewards, account);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    public entry fun set_reward_duration(
        _: &AdminCap, 
        reward_state: &mut RewardState, 
        duration: u64, 
        clock: &Clock
    ) {
        assert!(reward_state.finish_at < clock::timestamp_ms(clock), ERewardDurationNotExpired);

        reward_state.duration = duration;
        event::emit(RewardDurationUpdated { new_duration: duration });
    }

    public entry fun add_rewards(
        _: &AdminCap, 
        reward: Coin<MOCK_SWHIT>, 
        user_state: &mut UserState, 
        reward_state: &mut RewardState, 
        treasury: &mut Treasury, 
        clock: &Clock
    ) {
        let total_staked_supply = balance::value(&treasury.staked_coins_treasury);
        let amount = coin::value(&reward);

        update_reward(total_staked_supply, @0x0, user_state, reward_state, clock);

        let balance = coin::into_balance(reward);
        balance::join(&mut treasury.rewards_treasury, balance);

        if (clock::timestamp_ms(clock) >= reward_state.finish_at) {
            reward_state.reward_rate = amount / reward_state.duration;
        } else {
            let remaining_reward = (reward_state.finish_at - clock::timestamp_ms(clock)) * reward_state.reward_rate;
            reward_state.reward_rate = (amount + remaining_reward) / reward_state.duration;
        };

        assert!(reward_state.reward_rate > 0, EZeroRewardRate);
        assert!(reward_state.reward_rate * reward_state.duration <= balance::value(&treasury.rewards_treasury), ELowRewardsTreasuryBalance);

        reward_state.finish_at = clock::timestamp_ms(clock) + reward_state.duration;
        reward_state.updated_at = clock::timestamp_ms(clock);

        event::emit(RewardAdded { reward: amount });
    }

    /* ========== HELPER FUNCTIONS ========== */

    fun update_reward(
        total_staked_supply: u64, 
        account: address, 
        user_state: &mut UserState, 
        reward_state: &mut RewardState, 
        clock: &Clock
    ) {
        user_state.reward_per_token_stored = reward_per_token(total_staked_supply, user_state, reward_state, clock);
        reward_state.updated_at = u64::min(clock::timestamp_ms(clock), reward_state.finish_at);

        if (account != @0x0) {
            let new_reward_value = earned(total_staked_supply, account, user_state, reward_state, clock);
            let rewards_account = vec_map::get_mut(&mut user_state.rewards, &account);
            *rewards_account = new_reward_value;

            let user_reward_per_token_paid_account = vec_map::get_mut(&mut user_state.user_reward_per_token_paid, &account);
            *user_reward_per_token_paid_account = user_state.reward_per_token_stored;
        }
    }

    fun earned(
        total_staked_supply: u64, 
        account: address, 
        user_state: &UserState, 
        reward_state: &RewardState, 
        clock: &Clock
    ): u64 {
        let balance_of_account = (*vec_map::get(&user_state.balance_of, &account) as u256);
        let user_reward_per_token_paid_account = (*vec_map::get(&user_state.user_reward_per_token_paid, &account) as u256);
        let rewards_account = (*vec_map::get(&user_state.rewards, &account) as u256);
        let token_decimals = (u64::pow(10, 9) as u256);

        let rewards_earned  = ((balance_of_account * ((reward_per_token(total_staked_supply, user_state, reward_state, clock) as u256) - user_reward_per_token_paid_account)) / token_decimals) + rewards_account;

        (rewards_earned as u64)
    }

    fun reward_per_token(
        total_staked_supply: u64, 
        user_state: &UserState, 
        reward_state: &RewardState, 
        clock: &Clock
    ): u64 {
        if (total_staked_supply == 0) { 
            return user_state.reward_per_token_stored
        };

        let token_decimals = (u64::pow(10, 9) as u256);
        let last_time_reward_applicable = (u64::min(clock::timestamp_ms(clock), reward_state.finish_at) as u256);

        let computed_reward_per_token = (user_state.reward_per_token_stored as u256) + 
            ((reward_state.reward_rate as u256) * (last_time_reward_applicable - (reward_state.updated_at as u256)) * token_decimals) / 
            (total_staked_supply as u256);

        (computed_reward_per_token as u64)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}

