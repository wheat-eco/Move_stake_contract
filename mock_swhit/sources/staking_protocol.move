module devnet_staking::staking_protocol {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext}; 
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::math;
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::event;
    use devnet_staking::mock_swhit::MOCK_SWHIT;

    /* ========== OBJECTS ========== */

    struct RewardState has key {
        id: UID,
        duration: u64,
        finishAt: u64,
        updatedAt: u64,
        rewardRate: u64,
    }

    struct UserState has key {
        id: UID,
        rewardPerTokenStored: u64,
        userRewardPerTokenPaid: VecMap<address, u64>,
        balanceOf: VecMap<address, u64>,
        rewards: VecMap<address, u64>,
    }

    struct Treasury has key {
        id: UID,
        rewardsTreasury: Balance<MOCK_SWHIT>,
        stakedCoinsTreasury: Balance<SUI>,
    }

    struct AdminCap has key {
        id: UID
    }

    /* ========== EVENTS ========== */

    struct RewardAdded has copy, drop {
        reward: u64
    }

    struct RewardDurationUpdated has copy, drop {
         newDuration: u64
    }

    struct Staked has copy, drop {
        user: address,
        amount: u64
    }

    struct Withdrawn has copy, drop {
        user: address,
        amount: u64
    }

    struct RewardPaid has copy, drop {
        user: address,
        reward: u64
    }

    /* ========== ERRORS ========== */

    const ERewardDurationNotExpired: u64 = 100;
    const EZeroRewardRate: u64 = 101;
    const EZeroAmount: u64 = 102;
    const ELowRewardsTreasuryBalance: u64 = 103;
    const ERequestedAmountExceedsStaked: u64 = 104;
    const ENoRewardsToClaim: u64 = 105;
    const ENoStakedTokens: u64 = 106;
    const ENoPriorTokenStake: u64 = 107;

    /* ========== CONSTRUCTOR ========== */

    fun init(ctx: &mut TxContext) {
        transfer::share_object(RewardState {
            id: object::new(ctx),
            duration: 0,
            finishAt: 0,
            updatedAt: 0,
            rewardRate: 0
        });

        transfer::share_object(UserState {
            id: object::new(ctx),
            rewardPerTokenStored: 0,
            userRewardPerTokenPaid: vec_map::empty<address, u64>(),
            balanceOf: vec_map::empty<address, u64>(),
            rewards: vec_map::empty<address, u64>()
        });

        transfer::share_object(Treasury {
            id: object::new(ctx),
            rewardsTreasury: balance::zero<MOCK_SWHIT>(),
            stakedCoinsTreasury: balance::zero<SUI>(),
        });

        transfer::transfer(AdminCap {id: object::new(ctx)}, tx_context::sender(ctx));
    }

    /* ========== USER FUNCTIONS ========== */

    public entry fun stake(
        payment: Coin<SUI>, 
        userState: &mut UserState, 
        rewardState: &mut RewardState, 
        treasury: &mut Treasury, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let account = tx_context::sender(ctx);
        let totalStakedSupply = balance::value(&treasury.stakedCoinsTreasury);
        let amount = coin::value(&payment);

        if (!vec_map::contains(&userState.balanceOf, &account)) {
            vec_map::insert(&mut userState.balanceOf, account, 0);
            vec_map::insert(&mut userState.userRewardPerTokenPaid, account, 0);
            vec_map::insert(&mut userState.rewards, account, 0);
        };

        updateReward(totalStakedSupply, account, userState, rewardState, clock);

        let balance = coin::into_balance(payment);
        balance::join(&mut treasury.stakedCoinsTreasury, balance);

        let balanceOf_account = vec_map::get_mut(&mut userState.balanceOf, &account);
        *balanceOf_account = *balanceOf_account + amount;

        event::emit(Staked{user: account, amount});
    }

    public entry fun withdraw(
        userState: &mut UserState, 
        rewardState: &mut RewardState, 
        treasury: &mut Treasury, 
        amount: u64, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let account = tx_context::sender(ctx);
        let balanceOf_account_imut = vec_map::get(&userState.balanceOf, &account);
        let totalStakedSupply = balance::value(&treasury.stakedCoinsTreasury);

        assert!(vec_map::contains(&userState.balanceOf, &account), ENoStakedTokens);
        assert!(amount > 0, EZeroAmount);
        assert!(amount <= *balanceOf_account_imut, ERequestedAmountExceedsStaked);
        
        updateReward(totalStakedSupply, account, userState, rewardState, clock);

        let balanceOf_account = vec_map::get_mut(&mut userState.balanceOf, &account);
        *balanceOf_account = *balanceOf_account - amount;

        let withdrawalAmount = coin::take(&mut treasury.stakedCoinsTreasury, amount, ctx);
        transfer::public_transfer(withdrawalAmount, account);

        event::emit(Withdrawn{user: account, amount});
    }

    public entry fun getReward(
        userState: &mut UserState, 
        rewardState: &mut RewardState, 
        treasury: &mut Treasury, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        let account = tx_context::sender(ctx);
        let totalStakedSupply = balance::value(&treasury.stakedCoinsTreasury);

        assert!(vec_map::contains(&userState.rewards, &account), ENoPriorTokenStake);
        let rewards_account_imut = vec_map::get(&userState.rewards, &account);
        assert!(*rewards_account_imut > 0, ENoRewardsToClaim);

        updateReward(totalStakedSupply, account, userState, rewardState, clock);

        let rewards_account = vec_map::get_mut(&mut userState.rewards, &account);
        let stakingRewards = coin::take(&mut treasury.rewardsTreasury, *rewards_account, ctx);
        
        event::emit(RewardPaid{user: account, reward: *rewards_account});

        *rewards_account = 0;
        transfer::public_transfer(stakingRewards, account);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    public entry fun setRewardDuration(
        _: &AdminCap, 
        rewardState: &mut RewardState, 
        duration: u64, 
        clock: &Clock
    ) {
        assert!(rewardState.finishAt < clock::timestamp_ms(clock), ERewardDurationNotExpired);

        rewardState.duration = duration;
        event::emit(RewardDurationUpdated{newDuration: duration});
    }

    public entry fun addRewards(
        _: &AdminCap, 
        reward: Coin<MOCK_SWHIT>, 
        userState: &mut UserState, 
        rewardState: &mut RewardState, 
        treasury: &mut Treasury, 
        clock: &Clock
    ) {
        let totalStakedSupply = balance::value(&treasury.stakedCoinsTreasury);
        let amount = coin::value(&reward);

        updateReward(totalStakedSupply, @0x0, userState, rewardState, clock);

        let balance = coin::into_balance(reward);
        balance::join(&mut treasury.rewardsTreasury, balance);

        if (clock::timestamp_ms(clock) >= rewardState.finishAt) {
            rewardState.rewardRate = amount / rewardState.duration;
        } else {
            let remaining_reward = (rewardState.finishAt - clock::timestamp_ms(clock)) * rewardState.rewardRate;
            rewardState.rewardRate = (amount + remaining_reward) / rewardState.duration;
        };

        assert!(rewardState.rewardRate > 0, EZeroRewardRate);
        assert!(rewardState.rewardRate * rewardState.duration <= balance::value(&treasury.rewardsTreasury), ELowRewardsTreasuryBalance);

        rewardState.finishAt = clock::timestamp_ms(clock) + rewardState.duration;
        rewardState.updatedAt = clock::timestamp_ms(clock);

        event::emit(RewardAdded{reward: amount});
    }

    /* ========== HELPER FUNCTIONS ========== */

    fun updateReward(
        totalStakedSupply: u64, 
        account: address, 
        userState: &mut UserState, 
        rewardState: &mut RewardState, 
        clock: &Clock
    ) {
        userState.rewardPerTokenStored = rewardPerToken(totalStakedSupply, userState, rewardState, clock);
        rewardState.updatedAt = math::min(clock::timestamp_ms(clock), rewardState.finishAt);

        if (account != @0x0) {
            let new_reward_value = earned(totalStakedSupply, account, userState, rewardState, clock);
            let rewards_account = vec_map::get_mut(&mut userState.rewards, &account);
            *rewards_account = new_reward_value;

            let userRewardPerTokenPaid_account = vec_map::get_mut(&mut userState.userRewardPerTokenPaid, &account);
            *userRewardPerTokenPaid_account = userState.rewardPerTokenStored;
        }
    }

    fun earned(
        totalStakedSupply: u64, 
        account: address, 
        userState: &UserState, 
        rewardState: &RewardState, 
        clock: &Clock
    ): u64 {
        let balanceOf_account = (*vec_map::get(&userState.balanceOf, &account) as u256);
        let userRewardPerTokenPaid_account = (*vec_map::get(&userState.userRewardPerTokenPaid, &account) as u256);
        let rewards_account = (*vec_map::get(&userState.rewards, &account) as u256);
        let token_decimals = (math::pow(10, 9) as u256);

        let rewards_earned  = ((balanceOf_account * ((rewardPerToken(totalStakedSupply, userState, rewardState, clock) as u256) - userRewardPerTokenPaid_account)) / token_decimals) + rewards_account;

        (rewards_earned as u64)
    }

    fun rewardPerToken(
        totalStakedSupply: u64, 
        userState: &UserState, 
        rewardState: &RewardState, 
        clock: &Clock
    ): u64 {
        if (totalStakedSupply == 0) { 
            return userState.rewardPerTokenStored
        };

        let token_decimals = (math::pow(10, 9) as u256);
        let lastTimeRewardApplicable = (math::min(clock::timestamp_ms(clock), rewardState.finishAt) as u256);

        let computedRewardPerToken = (userState.rewardPerTokenStored as u256) + 
            ((rewardState.rewardRate as u256) * (lastTimeRewardApplicable - (rewardState.updatedAt as u256)) * token_decimals) / 
            (totalStakedSupply as u256);

        (computedRewardPerToken as u64)
    }
}

