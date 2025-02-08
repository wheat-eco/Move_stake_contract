module devnet_staking::staking_manager {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock::Clock;
    use sui::tx_context::TxContext;
    use devnet_staking::mock_swhit::{Self, MOCK_SWHIT};
    use devnet_staking::staking_protocol::{Self, AdminCap, RewardState, UserState, Treasury};

    public entry fun initialize_staking(
        treasury_cap: &mut TreasuryCap<MOCK_SWHIT>,
        admin_cap: &AdminCap,
        reward_state: &mut RewardState,
        user_state: &mut UserState,
        treasury: &mut Treasury,
        initial_reward_amount: u64,
        reward_duration: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Mint initial rewards
        let initial_rewards = coin::mint(treasury_cap, initial_reward_amount, ctx);

        // Set reward duration
        staking_protocol::setRewardDuration(admin_cap, reward_state, reward_duration, clock);

        // Add initial rewards
        staking_protocol::addRewards(admin_cap, initial_rewards, user_state, reward_state, treasury, clock);
    }

    public entry fun stake(
        payment: Coin<SUI>,
        user_state: &mut UserState,
        reward_state: &mut RewardState,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        staking_protocol::stake(payment, user_state, reward_state, treasury, clock, ctx);
    }

    public entry fun withdraw(
        user_state: &mut UserState,
        reward_state: &mut RewardState,
        treasury: &mut Treasury,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        staking_protocol::withdraw(user_state, reward_state, treasury, amount, clock, ctx);
    }

    public entry fun claim_reward(
        user_state: &mut UserState,
        reward_state: &mut RewardState,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        staking_protocol::getReward(user_state, reward_state, treasury, clock, ctx);
    }

    public entry fun add_rewards(
        admin_cap: &AdminCap,
        treasury_cap: &mut TreasuryCap<MOCK_SWHIT>,
        user_state: &mut UserState,
        reward_state: &mut RewardState,
        treasury: &mut Treasury,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let rewards = coin::mint(treasury_cap, amount, ctx);
        staking_protocol::addRewards(admin_cap, rewards, user_state, reward_state, treasury, clock);
    }
}

